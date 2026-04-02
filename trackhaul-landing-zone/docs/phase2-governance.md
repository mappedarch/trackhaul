# Phase 2 — Chaos to Governance Migration

## Background

Phase 1 established a GDPR-compliant AWS foundation from scratch. Phase 2 addresses a different problem — what happens when governance needs to be applied to an environment that was never designed with it in mind.

TrackHaul's Dev account had grown organically over several years without controls. Before Control Tower could be enrolled across the organisation, the existing state had to be understood, documented, and partially remediated. This phase covers that full journey: chaos simulation, pre-flight remediation, Control Tower enrollment, and automated account vending via AFT.

---

## Step 1 — Chaos Simulation

### Why

To validate that the Phase 1 governance controls worked as intended, and to establish a documented baseline of what an ungoverned account looks like before remediation. The chaos module introduces realistic misconfigurations that mirror what is commonly found in AWS accounts that grew without governance.

### What Was Simulated

Five misconfigurations were introduced into the Dev account via the `chaos-simulation/` Terraform module:

**1. IAM User with Long-Lived Access Key**
An IAM user with `AdministratorAccess` and no MFA enforcement. Modelled on a common finding — a developer account that was never deactivated after the person left. Inline policies were used deliberately because they are invisible to some AWS Config rules.

**2. CI/CD Service Account with AdministratorAccess**
A service account with `AdministratorAccess` attached. Modelled on the common pattern of over-permissioned CI/CD credentials stored in a third-party secrets store. The blast radius includes CloudTrail deletion, IAM user creation, and full S3 access.

**3. S3 Bucket with PII and No Encryption**
An unencrypted S3 bucket containing mock driver records and GPS coordinates. Versioning disabled, no access logging, no lifecycle policy. Violates GDPR Articles 5, 25, and 32.

**4. Security Group Open to the World**
A security group with ports 22 (SSH) and 3389 (RDP) open to `0.0.0.0/0`. Named with a "TEMP" suffix — a common pattern where temporary access groups are never cleaned up after the instance is terminated.

**5. No CloudTrail Data Events**
The Dev account had no CloudTrail data event logging. Without it, S3 object access and Lambda invocations leave no forensic trail. This makes all other findings worse — there is no way to determine whether the other misconfigurations were exploited.

### A Note on the Phase 1 SCPs

During chaos simulation, the `RequireS3Encryption` SCP from Phase 1 blocked creation of the unencrypted S3 bucket. This was not a failure — it was the SCP working as intended. It was documented as a positive finding: the preventive controls were in place and effective. The chaos module was adjusted to document this as a governance success rather than a gap.

### How to Deploy the Chaos Module

> **Warning:** This module introduces intentional misconfigurations. Deploy only in a dedicated non-production account. Never deploy in Prod.

```powershell
cd chaos-simulation
terraform init
terraform apply
```

### How to Destroy

```powershell
terraform destroy
```

All chaos resources are tagged `ManagedBy = chaos-simulation` for easy identification.

---

## Step 2 — Pre-flight Checks

Before Control Tower could be enrolled, several issues had to be resolved:

**Suspended accounts**
AWS accounts in a suspended state block CT enrollment. Any suspended accounts in the organisation must be resolved — either closed fully or restored to active — before proceeding.

**SCP conflict with CT**
The `RequireS3Encryption` SCP blocked CT's own S3 bucket creation during landing zone setup. CT uses the `AWSControlTowerExecution` role internally. A `StringNotLike` exemption was added to the SCP:

```hcl
StringNotLike = {
  "aws:PrincipalARN" = [
    "arn:aws:iam::*:role/AWSControlTowerExecution",
    "arn:aws:iam::*:role/aws-controltower-*",
    "arn:aws:iam::*:role/aws-controltower-ConfigRecorderRole*"
  ]
}
```

**Log Archive account placement**
The Log Archive account was originally placed in the Infrastructure OU. CT requires it to be in the Security OU to apply the `LogArchiveBaseline`. The account was moved in both the console and Terraform before CT enrollment.

**Suspended OU**
A `Suspended` OU was created and added to Terraform to provide a landing place for accounts that need to be quarantined without being closed.

---

## Step 3 — Control Tower Enrollment

### Landing Zone

Control Tower v4.0 was enrolled with `eu-central-1` as the home region. The landing zone ARN is stored in `modules/control-tower/main.tf` as an imported resource.

### Baseline Strategy

CT v4.0 uses `AWSControlTowerBaseline` v5.0 applied at the OU level — not the account level. The `enroll_ous.py` script handles enrollment dynamically, discovering all OUs from AWS Organizations at runtime with no hardcoded IDs.

```powershell
# Dry run first — lists OUs without applying
python scripts/enroll_ous.py --dry-run

# Apply enrollment
python scripts/enroll_ous.py
```

### OU Enrollment State

| Target | Baseline | Version | Notes |
|---|---|---|---|
| Workloads OU | AWSControlTowerBaseline | 5.0 | Dev and Prod accounts enrolled |
| Infrastructure OU | AWSControlTowerBaseline | 5.0 | Empty OU, enrolled for future accounts |
| Security Account | CentralSecurityRolesBaseline | — | Specialized baseline — CT requirement |
| Log Archive Account | LogArchiveBaseline | — | Specialized baseline — CT requirement |

### Why Security OU Accounts Get Different Baselines

CT treats Security OU accounts differently by design. The Security account and Log Archive account receive specialized baselines (`CentralSecurityRolesBaseline` and `LogArchiveBaseline`) rather than `AWSControlTowerBaseline`. These baselines set up centralized security monitoring roles and log aggregation infrastructure. Attempting to apply `AWSControlTowerBaseline` to these accounts directly returns a validation error.

### Terraform Provider Gap

The AWS Terraform provider does not support `aws_controltower_enabled_baseline` at the time of writing. CT baselines applied via the `enroll_ous.py` script cannot be imported into Terraform state. This is documented as a known provider gap. The script and its output serve as the record of what was applied.

---

## Step 4 — AFT Deployment

### What AFT Is

Account Factory for Terraform (AFT) is an AWS-maintained Terraform module that sets up a GitOps pipeline for account provisioning. When a new account request is pushed to the `aft-account-request` CodeCommit repository, a CodePipeline triggers automatically, calls CT Service Catalog to vend the account, and then runs account and global customizations.

### What AFT Deploys

AFT creates 344 resources across the AFT account and the Management account:

| Category | Resources | Purpose |
|---|---|---|
| Pipeline | 2 CodePipelines, 6 CodeBuild projects | Account request and customization pipelines |
| Repositories | 4 CodeCommit repos | Account requests, global and account customizations, provisioning customizations |
| Orchestration | 17 Lambda functions, 3 Step Functions | Account vending workflow and event handling |
| Storage | 5 S3 buckets, 5 DynamoDB tables | Pipeline artifacts, Terraform state, request tracking |
| Config | 64 SSM parameters | Pipeline configuration, backend references |
| Encryption | 4 KMS keys | Separate keys per service — S3, DynamoDB, SNS, SSM |
| Networking | 1 VPC, 4 subnets, 2 NAT Gateways, 16 VPC endpoints | Lambda runs inside a VPC; VPC endpoints reduce NAT costs |
| IAM | 38 roles, 32 role policies, 40 policy attachments | One role per pipeline stage per account |

### AFT Account Placement

A dedicated account was created for AFT under a dedicated `AFT` OU. This follows the AWS reference architecture — AFT is org-wide tooling and should not share an OU with workload or platform accounts.

The AFT account is created via Terraform in `modules/organizations/main.tf` and the AFT OU is enrolled into Control Tower before AFT is deployed.

### Prerequisites for AFT Deployment

Before running `terraform apply` in the `aft/` directory, the following must be in place:

1. The AFT account must exist in AWS Organizations
2. The AFT OU must be registered with Control Tower
3. The AFT account must be enrolled into Control Tower — the `AWSControlTowerExecution` role must exist in the AFT account
4. The `AWSAFTAdmin` role must exist in the Management account with a trust policy allowing the AFT account to assume it

### Deploying AFT

AFT is a separate Terraform root module with its own backend and state file.

```powershell
cd aft
Copy-Item terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with real account IDs

terraform init
terraform apply
```

> **Cost warning:** AFT deploys 2 NAT Gateways at approximately $32/month each. Destroy AFT when not actively vending accounts.

### Account Vending Flow

Clone the AFT CodeCommit repositories:

```powershell
git clone `
  --config credential.helper="!aws codecommit credential-helper $@" `
  --config credential.UseHttpPath=true `
  https://git-codecommit.eu-central-1.amazonaws.com/v1/repos/aft-account-request
```

Create an account request file in the `terraform/` directory:

```hcl
module "my_new_account" {
  source = "./modules/aft-account-request"

  control_tower_parameters = {
    AccountEmail              = "email@example.com"
    AccountName               = "my-new-account"
    ManagedOrganizationalUnit = "Workloads"
    SSOUserEmail              = "email@example.com"
    SSOUserFirstName          = "First"
    SSOUserLastName           = "Last"
  }

  account_tags = {
    Project     = "TrackHaul"
    ManagedBy   = "AFT"
    GDPR        = "true"
  }

  change_management_parameters = {
    change_requested_by = "platform-team"
    change_reason       = "New account request"
  }

  account_customizations_name = "my-new-account"
}
```

Push to trigger the pipeline:

```powershell
git add .
git commit -m "feat: add account request for my-new-account"
git push origin main
```

The `ct-aft-account-request` CodePipeline in the AFT account triggers automatically within 1–2 minutes.

### Destroying AFT

```powershell
cd aft
terraform destroy
```

Some resources require manual cleanup before `terraform destroy` completes:

- **S3 buckets with versioning** — empty all object versions first:
  ```powershell
  aws s3api list-object-versions `
    --bucket BUCKET-NAME `
    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' `
    --output json | Out-File versions.json

  aws s3api delete-objects `
    --bucket BUCKET-NAME `
    --delete file://versions.json
  ```

- **Backup vault with recovery points** — delete all recovery points before the vault can be removed:
  ```powershell
  aws backup list-recovery-points-by-backup-vault `
    --backup-vault-name aft-controltower-backup-vault `
    --region eu-central-1 `
    --query "RecoveryPoints[].RecoveryPointArn" `
    --output text
  ```
  Then delete each recovery point individually before retrying `terraform destroy`.

---

## Known Gotchas

### CT-Managed SCPs Block Manual Role Creation
CT deploys its own SCPs to enrolled OUs automatically. These SCPs block IAM role creation unless the principal is `AWSControlTowerExecution` or `stacksets-exec-*`. This creates a catch-22 when creating the `AWSControlTowerExecution` role itself in a new account.

**Resolution:** Temporarily move the account to the root (outside any OU with CT-managed SCPs), create the role, then move the account back.

### CodeCommit Default Branch
The AFT pipeline watches the `main` branch. Git initialises new repositories with a `master` branch by default. The pipeline will not trigger until the branch is renamed.

```powershell
git branch -m master main
git push origin main
```

### Stale Service Catalog Provisioned Product
If a CT account enrollment attempt fails partway through, a Service Catalog provisioned product is left in `AVAILABLE` state. Subsequent enrollment attempts fail with "stack already exists." 

**Resolution:** Terminate the provisioned product first:
```powershell
aws servicecatalog scan-provisioned-products `
  --region eu-central-1 `
  --query "ProvisionedProducts[?Name=='Enroll-Account-ACCOUNT_ID']"

aws servicecatalog terminate-provisioned-product `
  --provisioned-product-id PROVISIONED_PRODUCT_ID `
  --region eu-central-1 `
  --ignore-errors
```

### CT Does Not Support Account-Level Baseline Enrollment
The CT API `enable_baseline` only accepts OU ARNs as `targetIdentifier` — not account ARNs. Individual accounts are enrolled by ensuring they are in an enrolled OU. CT applies the baseline to new accounts in an enrolled OU automatically.

### AFT Terraform Provider Requires AWS Provider ~> 6.0
The AFT module (`aws-ia/control_tower_account_factory/aws` v1.18.1+) requires AWS provider `~> 6.0`. If the `aft/` module shares a provider with the landing zone root module, a version conflict will occur. Keep `aft/` as a completely separate root module with its own backend and provider configuration.

### NAT Gateway Cost
AFT deploys 2 NAT Gateways by default — one per availability zone. At approximately $32/month each, this is the dominant ongoing cost of an AFT deployment. Destroy AFT when it is not actively being used for account vending.

---

## Terraform Provider Gaps

| Gap | Detail |
|---|---|
| `aws_controltower_enabled_baseline` | Not supported. CT baselines applied via `enroll_ous.py` cannot be imported into Terraform state. |
| CT-managed SCPs | SCPs deployed by CT during landing zone setup are not manageable via Terraform. They are owned by CT and must not be modified directly. |

---

*Previous: [Phase 1 — Landing Zone](phase1-landing-zone.md)*  
*Next: Phase 3 — Enterprise Compliance (coming soon)*
