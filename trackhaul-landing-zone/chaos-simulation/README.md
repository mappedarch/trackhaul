# Chaos Simulation Module

## Purpose

This module creates intentionally misconfigured AWS resources in the TrackHaul
Dev account to simulate the "before" state prior to Control Tower governance migration.

**Every resource in this module is a real anti-pattern.** The comments explain why.
This is used for:
1. Portfolio demonstration — showing what chaos looks like before remediation
2. Blog content — the audit narrative in `docs/phase2-chaos-narrative.md`
3. Pre-flight testing — verifying that Control Tower SCPs block these patterns after enrollment

## Prerequisites

- AWS CLI configured with Management account credentials
- Terraform >= 1.5.0
- OrganizationAccountAccessRole must exist in Dev account (created in Phase 1)

## Usage

### Deploy the chaos state (Dev account only)

```powershell
# Navigate to the module
cd C:\files\nitya\workspace\trackhaul\trackhaul-landing-zone\chaos-simulation

# Initialise with local state (intentional — chaos has no remote state)
terraform init

# Preview what will be created
terraform plan

# Deploy — this creates the misconfigured resources
terraform apply -auto-approve

# Review the findings in the output
terraform output chaos_findings_summary
```

### Capture evidence for the blog / portfolio

```powershell
# Save the findings output to a file
terraform output -json chaos_findings_summary | Out-File -FilePath ..\docs\chaos-findings.json

# List the IAM users created (shows the chaos state)
aws iam list-users --profile dev-admin --query "Users[?starts_with(UserName,'trackhaul')]"

# Show the open security group (shows port 22 open)
aws ec2 describe-security-groups `
  --filters "Name=group-name,Values=trackhaul-debug-ssh-TEMP" `
  --profile dev-admin `
  --region eu-central-1
```

### Destroy before Control Tower enrollment

```powershell
# REQUIRED: Run this before Step 3 (Control Tower enrollment)
# CT enrollment will fail if IAM users exist that conflict with its guardrails
terraform destroy -auto-approve

# Verify IAM users are gone
aws iam list-users --profile dev-admin --query "Users[?starts_with(UserName,'trackhaul')]"
# Expected output: []
```

## Findings

| # | Resource | Anti-pattern | Remediation |
|---|---|---|---|
| 1 | IAM user `trackhaul-dev-admin` | Long-lived access key, no MFA | CT SCP denies `iam:CreateUser` |
| 2 | IAM user `trackhaul-ci-deploy` | `AdministratorAccess` on CI | Replace with OIDC in Phase 4 |
| 3 | S3 bucket `trackhaul-dev-data-2021-temp` | No SSE, no versioning, PII | LZA enforces encryption org-wide |
| 4 | Security group `trackhaul-debug-ssh-TEMP` | Port 22+3389 to `0.0.0.0/0` | Config rule `restricted-ssh` + CT guardrail |
| 5 | (absent) CloudTrail | No audit trail in Dev | CT mandatory trail, non-disableable |

## Important Notes

- This module uses **local Terraform state** deliberately — that is part of the chaos narrative
- Do **not** commit `terraform.tfstate` to git — add it to `.gitignore`
- Run `terraform destroy` before Phase 2 Step 3 or Control Tower enrollment will fail
