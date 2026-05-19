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

