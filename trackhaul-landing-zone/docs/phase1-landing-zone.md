# Phase 1 — GDPR-Compliant AWS Landing Zone

## Background

TrackHaul operates across three EU jurisdictions — Germany, Poland, and the Netherlands. Fleet telemetry, driver records, and operational data are all subject to GDPR. Before any application workload could be built, a governance foundation was required that enforced data residency, provided an immutable audit trail, and separated concerns between environments.

A single AWS account was ruled out. It would create a shared blast radius between development and production, make it impossible to enforce different controls per environment, and provide no clean audit boundary. A 5-account structure under AWS Organizations was chosen instead.

The phase 1 goal was to build this foundation from scratch — a GDPR-compliant multi-account landing zone, fully automated via Terraform, with security controls embedded at every layer.

---

## Architecture

### Account Structure

```
Root
├── Management OU
│   └── Management Account        — Org governance only, zero workloads
├── Security OU
│   ├── Security Account          — GuardDuty + Security Hub delegated admin
│   └── Log Archive Account       — Immutable CloudTrail logs, WORM storage
├── Infrastructure OU
│   └── (reserved for future platform tooling)
└── Workloads OU
    ├── Dev Account                — Developer sandbox
    └── Prod Account               — Production workloads
```

### Why This Structure

| Decision | Reasoning |
|---|---|
| Separate Security account | Centralises threat detection and security findings. Developers cannot access or modify security tooling. |
| Separate Log Archive account | CloudTrail logs are written to a dedicated account with Object Lock. Even if a workload account is compromised, logs cannot be tampered with. |
| Infrastructure OU | Reserved for platform tooling — VPN, DNS, shared services. Kept empty in Phase 1 to avoid premature complexity. |
| Workloads OU | Dev and Prod are separated at the account level. SCPs enforce different controls per OU in future phases. |
| Management account zero-workloads | AWS recommendation. The Management account has elevated trust and is excluded from SCPs by design. No application code runs here. |

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

## Key Architectural Decisions

### SCP Consolidation
AWS enforces a hard limit of 5 SCPs per target (OU or account). Rather than creating one SCP per control, all governance controls were consolidated into two SCPs:

- `trackhaul-governance` — blocks leaving the org, root usage, disabling CloudTrail, GuardDuty, and Security Hub
- `trackhaul-gdpr-data` — enforces EU region lock and S3 encryption

This leaves 3 SCP slots per OU available for future controls.

### EU Region Lock
A `DenyNonEURegions` SCP statement restricts all API calls to `eu-central-1` and `eu-west-1`. Global services (IAM, Organizations, Route53, STS, Support) are exempted via `NotAction` — these have no region concept and would break if blocked.

### GuardDuty and Security Hub Delegated Admin
Both services use a delegated administrator pattern. The Security account is designated as the delegated admin for the entire organisation. This means findings from all accounts flow into the Security account without requiring cross-account access from workload accounts.

### No Standing IAM Users
All human access is via IAM Identity Center with time-bound sessions. Three permission sets are defined:

| Permission Set | Access | Session Duration |
|---|---|---|
| AdministratorAccess | Management account only | 1 hour |
| DevAccess | Dev account, PowerUser | 8 hours |
| ReadOnlyAccess | All accounts | 8 hours |

### CloudTrail WORM Storage
Organisation-wide CloudTrail logs are written to an S3 bucket in the Log Archive account with Object Lock in Compliance mode. A 7-year retention period is enforced. No principal — including root — can modify or delete logs within this period.

---

## Prerequisites

### Tools

| Tool | Version | Purpose |
|---|---|---|
| Terraform | >= 1.6.0 | Infrastructure provisioning |
| AWS CLI | >= 2.0 | Bootstrap and CLI operations |
| Git | >= 2.0 | Version control |

### AWS Requirements

- AWS Organizations enabled with all features active
- IAM user or role with the following permissions in the Management account:
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

### Manual Steps Before Terraform

Two services must be enabled manually before Terraform runs — they cannot be enabled via API on first use:

**1. IAM Identity Center**
1. Log into the Management account AWS Console
2. Navigate to IAM Identity Center
3. Click Enable
4. Select `eu-central-1` as the home region
5. Keep Identity Center directory as the identity source

Retrieve the instance details after enabling:

```powershell
aws sso-admin list-instances --region eu-central-1
```

Note the `InstanceArn` and `IdentityStoreId` — these are required in `terraform.tfvars`.

**2. Trusted Access for AWS Services**

```powershell
aws organizations enable-aws-service-access `
  --service-principal cloudtrail.amazonaws.com

aws organizations enable-aws-service-access `
  --service-principal config.amazonaws.com

aws organizations enable-aws-service-access `
  --service-principal config-multiaccountsetup.amazonaws.com

aws organizations enable-aws-service-access `
  --service-principal guardduty.amazonaws.com

aws organizations enable-aws-service-access `
  --service-principal securityhub.amazonaws.com
```

---

## Deployment

### Step 1 — Bootstrap Terraform State Backend

The state backend must exist before Terraform runs. Create it once manually.

```powershell
# Create S3 bucket for Terraform state
aws s3api create-bucket `
  --bucket YOUR-STATE-BUCKET-NAME `
  --region eu-central-1 `
  --create-bucket-configuration LocationConstraint=eu-central-1

# Enable versioning
aws s3api put-bucket-versioning `
  --bucket YOUR-STATE-BUCKET-NAME `
  --versioning-configuration Status=Enabled

# Block all public access
aws s3api put-public-access-block `
  --bucket YOUR-STATE-BUCKET-NAME `
  --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Enable encryption
aws s3api put-bucket-encryption `
  --bucket YOUR-STATE-BUCKET-NAME `
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Create DynamoDB lock table
aws dynamodb create-table `
  --table-name trackhaul-terraform-locks `
  --attribute-definitions AttributeName=LockID,AttributeType=S `
  --key-schema AttributeName=LockID,KeyType=HASH `
  --billing-mode PAY_PER_REQUEST `
  --region eu-central-1
```

Update `backend.tf` with your bucket name before running `terraform init`.

### Step 2 — Configure Variables

```powershell
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

### Step 3 — Deploy

```powershell
terraform init
terraform plan
terraform apply
```

Account creation takes 2–5 minutes per account. The full apply takes approximately 15–20 minutes on first run.

### Step 4 — Import Existing Resources (if applicable)

If AWS Organizations or any services are already partially configured in your environment, import them before applying. Terraform will error if it tries to create a resource that already exists.

```powershell
# Import existing Organization
terraform import module.organizations.data.aws_organizations_organization.this default

# Import existing Management account
terraform import module.organizations.aws_organizations_account.management YOUR_MANAGEMENT_ACCOUNT_ID

# Import existing Security account
terraform import module.organizations.aws_organizations_account.security YOUR_SECURITY_ACCOUNT_ID

# Import existing GuardDuty detector
terraform import module.guardduty.aws_guardduty_detector.management YOUR_DETECTOR_ID

# Import existing Security Hub
terraform import module.securityhub.aws_securityhub_account.security YOUR_SECURITY_ACCOUNT_ID
```

---

## Module Reference

| Module | Path | What It Creates |
|---|---|---|
| organizations | `modules/organizations` | OUs, member accounts, account placement |
| scp | `modules/scp` | Consolidated SCPs, OU attachments |
| iam-identity-center | `modules/iam-identity-center` | Permission sets, groups, account assignments |
| cloudtrail | `modules/cloudtrail` | Organization trail, WORM S3 bucket in Log Archive account |
| config | `modules/config` | Config recorder, 8 compliance rules, aggregator |
| guardduty | `modules/guardduty` | Detector, delegated admin to Security account, org-wide config |
| securityhub | `modules/securityhub` | Hub enablement, delegated admin, CIS benchmark standard |
| budgets | `modules/budgets` | Per-account monthly budgets with email alerts at 80% and 100% |

---

## Known Gotchas

**SCP blocking CT role operations**
If Control Tower is enrolled later (Phase 2), the `RequireS3Encryption` SCP will block CT's own S3 bucket creation. CT uses the `AWSControlTowerExecution` role internally. Add a `StringNotLike` exemption for this role to the SCP before enrolling Control Tower.

**SCP 5-per-target limit**
AWS enforces a hard limit of 5 SCPs per OU or account. Consolidate controls into as few SCPs as possible from the start. Adding more SCPs later requires detaching existing ones first.

**GuardDuty delegated admin ordering**
The Security account must be created and the GuardDuty detector enabled in it before designating it as delegated admin. Terraform dependency ordering must be explicit — use `depends_on` or pass the detector ID as an output.

**Account creation is irreversible**
`aws_organizations_account` resources should always include `lifecycle { prevent_destroy = true }`. AWS account closure takes up to 90 days and cannot be undone immediately.

**IAM Identity Center home region**
The home region cannot be changed after Identity Center is enabled. Choose `eu-central-1` from the start and do not change it.

---

## Security Considerations

### Data Residency
All resources are restricted to `eu-central-1` and `eu-west-1` via SCP. Enforced at the Organisation level — no account administrator can override this. Satisfies GDPR Article 44.

### Audit Trail
CloudTrail logs are stored with Object Lock in Compliance mode. No principal — including root — can modify or delete logs for 7 years. Satisfies GDPR Article 30.

### Identity
No IAM users exist in any account. All human access is via IAM Identity Center with role-based permission sets and time-limited sessions.

### Encryption
All S3 buckets are encrypted with AES-256. The `RequireS3Encryption` SCP blocks creation of unencrypted S3 buckets. Config rules enforce EBS and RDS encryption. Satisfies GDPR Article 32.

### Least Privilege
- Developers have no access to Prod
- Platform team has ReadOnly on Prod
- No standing admin access in any account
- Production deployments handled by CI/CD pipeline via OIDC (Phase 4)

---

## GDPR Compliance Map

| GDPR Article | Requirement | Implementation |
|---|---|---|
| Article 25 | Data protection by design | SCPs enforce EU residency at infrastructure level |
| Article 30 | Records of processing | CloudTrail Organisation trail, 7-year WORM retention |
| Article 32 | Security of processing | Encryption enforced via SCPs and Config rules |
| Article 44 | International transfer restrictions | Deny non-EU regions SCP |

---

## Cost Estimates
Setting costs just for demo purposes.

| Account | Monthly Budget |
|---|---|
| Management | $10 |
| Security | $10 |
| Log Archive | $10 |
| Dev | $10 |
| Prod | $10 |

Budget alerts fire via email at 80% forecasted and 100% actual spend.

---

*Next: [Phase 2 — Chaos to Governance](phase2-governance.md)*
