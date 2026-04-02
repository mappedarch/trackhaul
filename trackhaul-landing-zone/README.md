# TrackHaul — AWS Multi-Account Landing Zone

TrackHaul is a fast-growing fictional European logistics company managing up to 10,000 trucks across Germany, Poland, and the Netherlands. This repository contains the full AWS infrastructure for TrackHaul's cloud platform — built on a GDPR-compliant multi-account foundation and progressively hardened through governance automation.

All infrastructure is managed via Terraform. No manual console actions are taken without a corresponding reconciliation back into code.

---

## What This Repository Covers

The platform was built in phases. Each phase builds on the previous one and is documented independently.

| Phase | Description | Status |
|---|---|---|
| [Phase 1 — Landing Zone](docs/phase1-landing-zone.md) | GDPR-compliant AWS foundation. Organizations, SCPs, IAM Identity Center, CloudTrail, Config, GuardDuty, Security Hub, Budgets. | Complete |
| [Phase 2 — Chaos to Governance](docs/phase2-governance.md) | Chaos simulation in Dev account, followed by full Control Tower enrollment and AFT deployment for automated account vending. | Complete |
| Phase 3 — Enterprise Compliance | Multi-regulation compliance layer. PCI-DSS, ISO 27001, NIS2, SOC2. | Planned |
| Phase 4 — Workloads | Application workloads on the governance foundation. | Planned |

---

## Account Structure

```
Root
├── Management OU
│   └── Management Account        — Org governance only, zero workloads
├── AFT OU
│   └── AFT Account               — Account Factory for Terraform pipeline
├── Security OU
│   ├── Security Account          — GuardDuty + Security Hub delegated admin
│   └── Log Archive Account       — Immutable CloudTrail logs, WORM storage
├── Infrastructure OU
│   └── (reserved for platform tooling)
└── Workloads OU
    ├── Dev Account                — Developer sandbox
    └── Prod Account               — Production workloads
```

---

## Control Layers

| Layer | Service | Purpose |
|---|---|---|
| Preventive | SCPs | Enforce EU data residency, block destructive actions |
| Identity | IAM Identity Center | Role-based SSO, zero standing IAM users |
| Audit | CloudTrail | Immutable organization-wide API audit trail |
| Compliance | AWS Config | Continuous compliance monitoring across all accounts |
| Detection | GuardDuty | Threat detection across all accounts |
| Aggregation | Security Hub | Single pane of glass for security findings |
| Governance | Control Tower | Landing zone enforcement, OU baseline management |
| Vending | AFT | GitOps account provisioning pipeline |
| Cost | Budgets | Per-account cost alerts at 80% and 100% |

---

## Repository Structure

```
trackhaul-landing-zone/
├── main.tf                        — Root module, orchestrates all child modules
├── variables.tf                   — Input variable declarations
├── terraform.tfvars.example       — Variable template (copy to terraform.tfvars)
├── backend.tf                     — Remote state configuration
├── aft/                           — AFT root module (separate Terraform deployment)
├── chaos-simulation/              — Chaos simulation module (Phase 2)
├── modules/
│   ├── organizations/             — OUs and member accounts
│   ├── scp/                       — Service Control Policies
│   ├── iam-identity-center/       — SSO permission sets and assignments
│   ├── cloudtrail/                — Organization-wide audit trail
│   ├── config/                    — Compliance rules and aggregator
│   ├── guardduty/                 — Threat detection
│   ├── securityhub/               — Security findings aggregation
│   ├── budgets/                   — Per-account cost alerts
│   └── control-tower/             — Control Tower landing zone
├── scripts/
│   └── enroll_ous.py              — Dynamic OU enrollment into Control Tower
└── docs/
    ├── phase1-landing-zone.md     — Phase 1 full documentation
    ├── phase2-chaos-narrative.md  — Chaos simulation audit narrative
    └── phase2-governance.md       — Phase 2 full documentation
```

---

## GDPR Compliance Map

| GDPR Article | Requirement | Implementation |
|---|---|---|
| Article 25 | Data protection by design | SCPs enforce EU residency at infrastructure level |
| Article 30 | Records of processing | CloudTrail Organization trail, 7-year WORM retention |
| Article 32 | Security of processing | Encryption enforced via SCPs and Config rules |
| Article 44 | International transfer restrictions | Deny non-EU regions SCP |

---

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Terraform | >= 1.6.0 | Infrastructure provisioning |
| AWS CLI | >= 2.0 | Bootstrap and CLI operations |
| Python | >= 3.10 | OU enrollment script |
| boto3 | latest | Python AWS SDK |
| Git | >= 2.0 | Version control |

---

## Where to Start

Read the phase documentation in order:

1. [Phase 1 — Landing Zone](docs/phase1-landing-zone.md)
2. [Phase 2 — Chaos to Governance](docs/phase2-governance.md)

Each document covers prerequisites, deployment steps, architectural decisions, and known gotchas specific to that phase.