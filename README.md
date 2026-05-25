# TrackHaul AI Fleet Intelligence Platform

A production-grade AWS platform built for TrackHaul, a fictional European logistics operator managing large number of trucks (e.g. 10,000). The platform covers GDPR-compliant multi-account governance, serverless fleet operations, real-time telemetry processing, and an AI fleet intelligence layer built on Amazon Bedrock.

All infrastructure is defined in Terraform using a modular structure. No manual console configuration is used. Security controls are applied at every layer.

---

## Projects

| # | Project | Status | Folder |
|---|---|---|---|
| 1 | Multi-Account Landing Zone | Done | [trackhaul-landing-zone](./trackhaul-landing-zone/) |
| 2 | Serverless Fleet Management API | Done | [trackhaul-fleet-api](./trackhaul-fleet-api/) |
| 3 | Event-Driven Processing Pipeline | Done | [trackhaul-event-pipeline](./trackhaul-event-pipeline/) |
| 4 | Real-Time Streaming Telemetry | Done | [trackhaul-streaming](./trackhaul-streaming/) |
| 5 | AI Fleet Intelligence Layer | Planned | - |
| 6 | LLMOps and AIOps | Planned | - |
| 7 | Agentic AI and Multi-Agent System | Planned | - |

---

## Prerequisites

### Tools

| Tool | Version | Purpose |
|---|---|---|
| Terraform | >= 1.6 | Infrastructure as Code |
| AWS CLI | >= 2.13 | AWS authentication and CLI operations |
| Python | >= 3.11 | Lambda functions and AI layer |
| Git | Any | Version control |
| VSCode | Any | Editor |

### AWS Setup

- AWS Organizations enabled with a dedicated management account
- IAM Identity Center configured — all access uses short-lived SSO credentials
- Terraform remote state S3 bucket and DynamoDB lock table provisioned in the management account
- Primary region: `eu-central-1`
- DR region: `eu-west-1`

### Authentication

Authenticate via IAM Identity Center before running any Terraform commands. No long-lived IAM user credentials are used anywhere in this project.

```bash
# Authenticate via SSO
aws sso login --profile trackhaul-mgmt

# Verify identity
aws sts get-caller-identity --profile trackhaul-mgmt
```

---

## Repository Structure

```
trackhaul/
├── trackhaul-landing-zone/          # Project 1 — Multi-Account Landing Zone
├── trackhaul-fleet-api/             # Project 2 — Serverless Fleet API
├── trackhaul-event-pipeline/        # Project 3 — Event-Driven Pipeline
├── trackhaul-streaming/             # Project 4 — Real-Time Streaming Telemetry
├── trackhaul-ai/                    # Project 5 — AI Fleet Intelligence Layer (planned)
├── trackhaul-llmops/                # Project 6 — LLMOps and AIOps (planned)
├── trackhaul-agents/                # Project 7 — Agentic AI (planned)
└── README.md
```

---

## Usage

Each project folder contains its own README with project-specific deployment instructions. The general pattern for all projects is:

```bash
# 1. Navigate to the project folder
cd trackhaul-landing-zone

# 2. Authenticate via SSO
aws sso login --profile trackhaul-mgmt

# 3. Initialise Terraform with remote state
terraform init

# 4. Review the plan
terraform plan

# 5. Apply
terraform apply
```

---

## Security Considerations

| Control | Implementation |
|---|---|
| Data residency | SCPs enforce `eu-central-1` and `eu-west-1` only — no resource creation permitted outside EU |
| IAM access | No standing IAM users — all access via IAM Identity Center with short-lived credentials |
| Encryption | KMS customer managed keys per data classification boundary |
| PII isolation | No PII enters event payloads or LLM inputs — truck IDs only |
| Audit trail | Immutable CloudTrail logs in Log Archive account with WORM S3 Object Lock |
| AI data residency | All Bedrock inference in `eu-west-1` — enforced at IAM and SCP level |
| Least privilege | Every Lambda function and service has its own scoped execution role |

---

## Compliance

GDPR compliance is a primary design constraint throughout this platform. EU data residency is enforced at the SCP layer, not left to convention. Driver PII does not appear in any event payload, telemetry record, or LLM prompt. CloudTrail provides a complete audit trail of all API activity across all accounts.

---

## Blog Series

The architecture and implementation decisions across all projects are documented in a Medium article series.

| Part | Topic |
|---|---|
| Series Overview | [Building a GDPR-Compliant Fleet Intelligence Platform on AWS](https://mappedarch.medium.com/building-a-gdpr-compliant-fleet-intelligence-platform-on-aws-a-five-part-series-24cb116eab9a) |
| Part 1 | [Multi-Account Landing Zone](https://mappedarch.medium.com/building-a-gdpr-compliant-fleet-intelligence-platform-on-aws-phase-1-the-landing-zone-a4b3ab2dcff1) |
| Part 2 | [Chaos to Control - The Control Tower](https://mappedarch.medium.com/building-a-gdpr-compliant-fleet-intelligence-platform-on-aws-phase-1-the-landing-zone-a4b3ab2dcff1) |
| Part 3 | [Fleet Management API](https://medium.com/@mappedarch/fleet-intelligence-platform-on-aws-part-3-fleet-management-api-2467e6fd19db) |

*Remaining parts are upcoming.*
