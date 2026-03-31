# TrackHaul Phase 2 — The Chaos State: What We Inherited

> This document describes TrackHaul's AWS environment *before* the Control Tower
> + AFT + LZA governance migration. It is authored as an audit narrative —
> the kind of document a Solutions Architect produces on day one of an
> enterprise engagement to establish a baseline before remediating.

---

## Background

TrackHaul GmbH started as a three-person logistics startup in Berlin in 2018.
By 2024 they had 10,000 trucks across Germany, Poland, and the Netherlands,
and their AWS footprint had grown the same way: organically, reactively, and
without governance.

The CTO's summary when we were engaged: *"We have five AWS accounts, nobody
knows who owns two of them, and we got a Security Hub finding last week that
nobody could explain."*

That is a completely normal starting point for a Series B European logistics company.
What follows is what we found.

---

## Finding #1 — IAM Users with Long-Lived Access Keys

**Account:** Dev (386324384619)
**Resource:** `iam:user/trackhaul-dev-admin`

An IAM user created in 2020 for a developer who has since left the company.
The access key was never deactivated. MFA was never enforced. The key had
`AdministratorAccess`-equivalent permissions via an inline policy.

Inline policies are particularly dangerous because:
- They do not appear in the IAM console's managed policy view
- They are invisible to AWS Config rules that check `iam-user-no-policies-check`
  (that rule only catches managed policy attachments, not inline)
- They survive user renames in some edge cases

**GDPR relevance:** If this key was ever used to access personal data (truck GPS,
driver IDs), there is no audit trail in the Dev account to prove or disprove it —
see Finding #5.

**Remediation:** Control Tower SCP `AWS-GR_RESTRICT_ROOT_ACCOUNT` and our custom
`trackhaul-governance` SCP will deny `iam:CreateUser` and `iam:CreateAccessKey`
org-wide. Existing users must be deleted manually before enrollment.

---

## Finding #2 — CI/CD Pipeline with AdministratorAccess

**Account:** Dev (386324384619)
**Resource:** `iam:user/service-accounts/trackhaul-ci-deploy`

A service account used by the GitHub Actions pipeline. At some point someone
attached `arn:aws:iam::aws:policy/AdministratorAccess` because the pipeline
needed to provision infrastructure and the team didn't know how to scope it.

The access key for this user was stored in GitHub Actions secrets — which means
anyone with write access to the repository could exfiltrate it via a malicious
workflow.

**The blast radius:** This one account can delete CloudTrail logs, create new IAM
users, launch EC2 instances for crypto-mining, and exfiltrate data from every S3
bucket in the account. AWS has a dedicated threat intelligence team that monitors
for compromised access keys being used on TOR exit nodes. This key would be on
their list.

**Remediation:** Phase 4 replaces all access key-based CI/CD with GitHub OIDC
federation. No long-lived credentials. Zero keys in GitHub secrets.

---

## Finding #3 — S3 Bucket with PII, No Encryption, No Access Logging

**Account:** Dev (386324384619)
**Resource:** `s3://trackhaul-dev-data-2021-temp`

Created for a one-time data migration in 2021. Still exists. Contains:
- Driver ID numbers (personal data under GDPR)
- Truck GPS coordinates (location data, personal data if driver identifiable)
- Route history

Missing controls:
- No server-side encryption (`aws:kms` or `AES256`) — data at rest is plaintext
- Versioning suspended — accidental deletes are permanent
- No access logging — cannot prove who accessed what
- No object lifecycle policy — data lives forever
- Bucket policy allows `s3:*` to any account principal — too broad

**GDPR Articles violated:**
- Article 5(1)(e) — storage limitation (data retained beyond its purpose)
- Article 25 — data protection by design (no encryption by default)
- Article 32 — security of processing (no technical measures)

**Remediation:** LZA will enforce S3 encryption at the org level via SCP and
Config rule `s3-bucket-server-side-encryption-enabled`. Macie will scan the
bucket for PII and flag it for remediation.

---

## Finding #4 — Security Group with Ports 22 and 3389 Open to the World

**Account:** Dev (386324384619)
**Resource:** `ec2:security-group/trackhaul-debug-ssh-TEMP`

The group name includes "TEMP" and "TODO remove." It was created in 2022 and
the EC2 instance it was attached to was terminated, but the security group
itself was never deleted.

Security groups in AWS are not cleaned up automatically when instances terminate.
They sit in the VPC silently. If any future instance is launched and a developer
selects "use existing security group" from the dropdown, this group can be
re-attached instantly.

Port 22 (SSH) and 3389 (RDP) open to `0.0.0.0/0` means any IP on the internet
can attempt to connect. Without a bastion host or VPN requirement, the only
protection is the instance's host-based firewall — which developers routinely
disable for "debugging."

**Remediation:** Config rule `restricted-ssh` (already deployed in Phase 1)
flags this as NON_COMPLIANT. Control Tower adds `AWS-GR_RESTRICTED_SSH` as
a proactive guardrail. LZA adds VPC baseline with no public subnets in dev.

---

## Finding #5 — No CloudTrail in the Dev Account

This is the most dangerous finding because it makes all the others worse.

Without CloudTrail:
- We cannot determine when Finding #1's access key was last used
- We cannot determine who accessed the S3 bucket in Finding #3
- We cannot determine who created the security group in Finding #4
- If a breach occurred, we have no forensic evidence
- GDPR Article 30 (records of processing activities) is violated

The Dev account was never enrolled in the organization CloudTrail from Phase 1.
The trail in the Management account captures management events org-wide, but
*data events* (S3 object reads, Lambda invocations) must be enabled per-account
or via a separate data events trail.

**Remediation:** Control Tower mandates a CloudTrail trail in every enrolled
account as a non-configurable guardrail. There is no way to disable it without
leaving Control Tower. This is the right architectural choice.

---

## The Governance Gap Summary

| Control | Management account | Dev account (before) |
|---|---|---|
| CloudTrail org trail | Yes | No |
| SCPs | Yes (2 consolidated) | Inherited but not enforced locally |
| IAM users | None (SSO only) | 2 active users, 2 access keys |
| S3 encryption | Enforced by Config | Not enforced |
| Security group audit | Config rule active | No Config in Dev |
| MFA enforcement | SSO MFA required | No IAM MFA policy |
| Resource tags | Required by SCP | Not required, not applied |

---

## What Phase 2 Fixes

Control Tower enrollment closes every gap in the table above — automatically,
at the account level, without manual intervention per resource.

AFT ensures that any *new* account vended in the future starts with the same
controls applied. No more "we'll add governance later" — governance is the
first thing that runs when an account is created.

LZA adds the networking and security service layer: VPC baseline, Security Hub
standards, GuardDuty threat intelligence, Macie PII scanning, and Config
conformance packs pre-configured for GDPR.

The chaos state above is not unusual. It is what almost every company looks like
before they engage a Solutions Architect. The value is not in knowing that these
things are wrong — it is in knowing *exactly how to fix them* at scale, across
multiple accounts, without breaking workloads that are already running.

---

*Document version: 1.0 — Phase 2 baseline audit*
*Prepared for: TrackHaul GmbH*
*AWS region scope: eu-central-1 (primary), eu-west-1 (DR)*
