# TrackHaul — Phase 1: GDPR-Compliant AWS Landing Zone

A GDPR-compliant AWS multi-account landing zone for TrackHaul, a fictional European logistics startup managing 10,000 trucks across Germany, Poland and the Netherlands. All infrastructure is managed via Terraform. Security controls are embedded at every layer.

---

## Architecture

```
Root
├── Management OU
│   └── Management Account (258335483092)   — Org governance only, zero workloads
├── Security OU
│   └── Security Account (893946677478)     — GuardDuty + Security Hub delegated admin
├── Infrastructure OU
│   └── Log Archive Account (143941265315)  — Immutable CloudTrail logs, WORM storage
└── Workloads OU
    ├── Dev Account (386324384619)           — Developer sandbox
    └── Prod Account (926028310051)          — Production workloads
```

### Control Layers

| Layer | Service | Purpose |
|---|---|---|
| Preventive | SCPs | Enforce EU data residency, block destructive actions |
| Identity | IAM Identity Center | Role-based SSO, zero standing IAM users |
| Audit | CloudTrail | Immutable organization-wide API audit trail |
| Compliance | AWS Config | Continuous compliance monitoring across all accounts |
| Detection | GuardDuty | Threat detection across all accounts |
| Aggregation | Security Hub | Single pane of glass for security findings |
| Cost | Budgets | Per-account cost alerts at 80% and 100% |

---

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Terraform | >= 1.6.0 | Infrastructure provisioning |
| AWS CLI | >= 2.0 | Bootstrap and CLI operations |
| Git | >= 2.0 | Version control |

### AWS Requirements

- AWS Organizations enabled with Management account access
- IAM user or role with the following permissions:
  - `organizations:*`
  - `iam:*`
  - `s3:*`
  - `dynamodb:*`
  - `cloudtrail:*`
  - `config:*`
  - `guardduty:*`
  - `securityhub:*`
  - `budgets:*`
  - `sso:*`
  - `sts:AssumeRole` on `arn:aws:iam::*:role/OrganizationAccountAccessRole`
- IAM Identity Center manually enabled in `eu-central-1` before applying

---

## Usage

### 1. Bootstrap the Terraform State Backend

The state backend must exist before Terraform runs. Create it once manually.

```powershell
# Create S3 bucket for Terraform state
aws s3api create-bucket `
  --bucket trackhaul-terraform-state-258335483092 `
  --region eu-central-1 `
  --create-bucket-configuration LocationConstraint=eu-central-1

# Enable versioning — allows state file rollback
aws s3api put-bucket-versioning `
  --bucket trackhaul-terraform-state-258335483092 `
  --versioning-configuration Status=Enabled

# Block all public access — state files contain sensitive data
aws s3api put-public-access-block `
  --bucket trackhaul-terraform-state-258335483092 `
  --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Enable encryption at rest
aws s3api put-bucket-encryption `
  --bucket trackhaul-terraform-state-258335483092 `
  --server-side-encryption-configuration '{\"Rules\":[{\"ApplyServerSideEncryptionByDefault\":{\"SSEAlgorithm\":\"AES256\"}}]}'

# Create DynamoDB table for state locking
aws dynamodb create-table `
  --table-name trackhaul-terraform-locks `
  --attribute-definitions AttributeName=LockID,AttributeType=S `
  --key-schema AttributeName=LockID,KeyType=HASH `
  --billing-mode PAY_PER_REQUEST `
  --region eu-central-1
```

### 2. Enable Required AWS Service Trusted Access

```powershell
# CloudTrail
aws organizations enable-aws-service-access `
  --service-principal cloudtrail.amazonaws.com

# Config
aws organizations enable-aws-service-access `
  --service-principal config.amazonaws.com
aws organizations enable-aws-service-access `
  --service-principal config-multiaccountsetup.amazonaws.com

# GuardDuty
aws organizations enable-aws-service-access `
  --service-principal guardduty.amazonaws.com

# Security Hub
aws organizations enable-aws-service-access `
  --service-principal securityhub.amazonaws.com
```

### 3. Enable IAM Identity Center

IAM Identity Center must be enabled manually before Terraform runs.

1. Log into the Management account AWS Console
2. Navigate to IAM Identity Center
3. Click Enable
4. Select `eu-central-1` as the home region
5. Keep Identity Center directory as the identity source

Retrieve the instance details after enabling:

```powershell
aws sso-admin list-instances --region eu-central-1
```

Note the `InstanceArn` and `IdentityStoreId` values for `terraform.tfvars`.

### 4. Configure Variables

```powershell
# Copy the example file
Copy-Item terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with real values:

```hcl
aws_region     = "eu-central-1"
aws_region_dr  = "eu-west-1"

management_account_id  = "YOUR_MANAGEMENT_ACCOUNT_ID"
security_account_id    = "YOUR_SECURITY_ACCOUNT_ID"
log_archive_account_id = "YOUR_LOG_ARCHIVE_ACCOUNT_ID"
dev_account_id         = "YOUR_DEV_ACCOUNT_ID"
prod_account_id        = "YOUR_PROD_ACCOUNT_ID"

org_id = "YOUR_ORG_ID"

management_email  = "YOUR_MANAGEMENT_EMAIL"
security_email    = "YOUR_SECURITY_EMAIL"
log_archive_email = "YOUR_LOG_ARCHIVE_EMAIL"
dev_email         = "YOUR_DEV_EMAIL"
prod_email        = "YOUR_PROD_EMAIL"

sso_instance_arn  = "YOUR_SSO_INSTANCE_ARN"
identity_store_id = "YOUR_IDENTITY_STORE_ID"

alert_email = "YOUR_ALERT_EMAIL"
```

### 5. Deploy

```powershell
# Initialise Terraform — downloads providers and configures backend
terraform init

# Preview changes — review carefully before applying
terraform plan

# Apply — type yes when prompted
terraform apply
```

### 6. Import Existing Resources

If services are already partially enabled in your accounts, import them before applying.

```powershell
# Import existing Organization
terraform import module.organizations.data.aws_organizations_organization.this default

# Import existing Management account
terraform import module.organizations.aws_organizations_account.management YOUR_MANAGEMENT_ACCOUNT_ID

# Import existing Security account
terraform import module.organizations.aws_organizations_account.security YOUR_SECURITY_ACCOUNT_ID

# Import existing GuardDuty detector
terraform import module.guardduty.aws_guardduty_detector.management YOUR_DETECTOR_ID

# Import existing Security Hub account
terraform import module.securityhub.aws_securityhub_account.security YOUR_SECURITY_ACCOUNT_ID
```

---

## Module Reference

| Module | Path | What It Creates |
|---|---|---|
| organizations | `modules/organizations` | OUs, member accounts, account placement |
| scp | `modules/scp` | Consolidated SCPs, OU attachments |
| iam-identity-center | `modules/iam-identity-center` | Permission sets, groups, account assignments |
| cloudtrail | `modules/cloudtrail` | Organization trail, WORM S3 bucket |
| config | `modules/config` | Config recorder, 8 compliance rules, aggregator |
| guardduty | `modules/guardduty` | Detector, delegated admin, org configuration |
| securityhub | `modules/securityhub` | Hub enablement, delegated admin, CIS standard |
| budgets | `modules/budgets` | Per-account cost budgets with email alerts |

---

## Security Considerations

### Data Residency
All resources are restricted to `eu-central-1` and `eu-west-1` via SCP. This is enforced at the Organization level and cannot be overridden by any account administrator. Satisfies GDPR Article 44.

### Audit Trail
CloudTrail logs are stored with Object Lock in Compliance mode. No principal — including root — can modify or delete logs for 7 years. Satisfies GDPR Article 30.

### Identity
No IAM users exist in any account. All human access is via IAM Identity Center with role-based permission sets. Emergency access via the BreakGlass role requires MFA and is limited to 1-hour sessions.

### Encryption
All S3 buckets are encrypted with AES-256. The deny-non-EU-regions SCP blocks creation of unencrypted S3 buckets. Config rules enforce EBS and RDS encryption. Satisfies GDPR Article 32.

### Least Privilege
- Developers have no access to Prod
- Platform team has ReadOnly on Prod
- Nobody has standing admin access to Prod
- Production deployments are handled by CI/CD pipeline via OIDC (Phase 4)

### Known Limits
- AWS enforces a maximum of 5 SCPs per target (OU or account)
- SCPs do not apply to the Management account — this is an AWS hard limit
- IAM Identity Center home region cannot be changed after enablement

---

## GDPR Compliance Map

| GDPR Article | Requirement | Implementation |
|---|---|---|
| Article 25 | Data protection by design | SCPs enforce EU residency at infrastructure level |
| Article 30 | Records of processing | CloudTrail Organization trail, 7 year WORM retention |
| Article 32 | Security of processing | Encryption enforced via SCPs and Config rules |
| Article 44 | International transfer restrictions | Deny non-EU regions SCP |

---

## Cost Estimates

| Account | Monthly Budget |
|---|---|
| Management | $50 |
| Security | $100 |
| Log Archive | $50 |
| Dev | $200 |
| Prod | $500 |

Budget alerts are sent via email at 80% forecasted and 100% actual spend.

---

## Related

- [Phase 2 — Chaos to Governance Migration](../trackhaul-phase2/README.md) — coming soon
- [Blog Post — Phase 1](../blog/phase1-landing-zone.md)
