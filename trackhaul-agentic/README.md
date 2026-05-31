# TrackHaul — Agentic AI and Multi-Agent Fleet System

![Python](https://img.shields.io/badge/Python-3.11-blue) ![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.6.0-purple) ![LangGraph](https://img.shields.io/badge/LangGraph-1.2.2-red) ![Bedrock](https://img.shields.io/badge/Bedrock-Claude%20Sonnet%204.5-orange) ![Region](https://img.shields.io/badge/Region-eu--central--1-green) ![License](https://img.shields.io/badge/License-MIT-lightgrey)

TrackHaul operates a fleet of 10,000 trucks across Germany, Poland and the Netherlands. Critical incidents — engine faults, geofence breaches, fuel anomalies — previously required manual investigation workflows that did not scale at fleet volume. This project implements an agentic AI system that autonomously diagnoses incidents, queries fleet and maintenance data, dispatches alerts and escalates where required — without human intervention in the critical path.

All infrastructure is defined in Terraform. All AI inference runs within `eu-central-1`. No PII enters any agent or LLM at any stage. GDPR compliance is enforced at the Bedrock Guardrail layer before any model invocation.

---

## Architecture

```
SQS Incident Queue (agent-queue module)
         |
         | batch_size=1 — one incident per agent run
         v
+---------------------------+
|  Lambda — agent_handler   |  reserved_concurrency = configurable
|  Compiled once at init    |  SQS event source mapping
+--------+------------------+
         |
         v
+---------------------------+
|  Orchestrator Agent       |  LangGraph StateGraph
|  orchestrator.py          |  Classifies incident type
|                           |  Routes to specialist worker
+----+--------+--------+----+
     |        |        |
     v        v        v
+--------+ +-------+ +--------+
|Incident| | Fuel  | | Safety |
|Respond | | Agent | | Agent  |
|er      | |       |         |
+---+----+ +---+---+ +---+----+
    |           |         |
    +-----+-----+---------+
          |
          v
+---------------------------+
|  Bedrock Guardrail        |  PII block, topic deny, word filters
|  bedrock-guardrail module |  Applied to raw query before LLM
+---------------------------+
          |
          v
+---------------------------+
|  Amazon Bedrock           |
|  Claude Sonnet 4.5        |
|  eu-central-1             |
+---------------------------+
          |
    +-----+------+
    |            |
    v            v
+--------+  +-----------+
|  MCP   |  |   MCP     |
| fleet_ |  | mainten-  |
| query  |  | ance      |
+--------+  +-----------+
    |
    v
+---------------+
|  MCP          |
| alert_dispatch|
+---------------+

Supporting infrastructure:
- SQS DLQ — failed incidents retained for manual review
- KMS CMK — SQS messages and Lambda environment encrypted
- CloudWatch Logs — full agent invocation audit trail
```

**Primary region:** eu-central-1
**Model:** Claude Sonnet 4.5 via Amazon Bedrock
**Agent framework:** LangGraph 1.2.2
**MCP transport:** stdio (servers run as subprocesses)
**No PII in any LLM prompt — truck IDs only**

---

## Agent Roles

| Agent | File | Responsibility |
|---|---|---|
| Orchestrator | `agents/orchestrator.py` | Classifies incident type, routes to specialist worker, aggregates result and produces final recommendation |
| Incident Responder | `agents/incident_responder.py` | Diagnoses fault codes, checks maintenance history, determines severity and recommended action |
| Fuel Agent | `agents/fuel_agent.py` | Detects and explains fuel anomalies against baseline, flags leaks vs consumption patterns |
| Safety Agent | `agents/safety_agent.py` | Evaluates driver behaviour patterns, scores harsh braking and hours compliance trends |
| Guardrails | `agents/guardrails.py` | Enforces PII boundaries and escalation rules. Blocks driver names, GPS coordinates and out-of-scope queries |

---

## MCP Servers

| Server | Path | Tools Exposed |
|---|---|---|
| Fleet Query | `mcp_servers/fleet_query/` | Query live vehicle status, open fault list, regional fleet summary — by truck ID only |
| Maintenance | `mcp_servers/maintenance/` | Retrieve maintenance records, service history, open work orders by truck ID |
| Alert Dispatch | `mcp_servers/alert_dispatch/` | Dispatch alerts to ops channels — gated by severity threshold |

MCP servers run as stdio subprocesses. Sessions are opened once per agent invocation and held open for the full duration of the run.

---

## Terraform Modules

| Module | Path | What It Creates |
|---|---|---|
| agent-queue | `modules/agent-queue/` | SQS incident queue, DLQ, Lambda function, execution role, SQS event source mapping with batch size 1, reserved concurrency cap |
| bedrock-guardrail | `modules/bedrock-guardrail/` | Bedrock guardrail with PII entity filters (NAME, EMAIL, PHONE, ADDRESS, LOCATION, DRIVER_ID), denied topic policy for out-of-scope queries, word filters for prompt injection patterns |

---

## Repository Structure

```
trackhaul-agentic/
├── agents/
│   ├── orchestrator.py          — Multi-agent orchestrator graph
│   ├── incident_responder.py    — Fault code diagnosis worker agent
│   ├── fuel_agent.py            — Fuel anomaly worker agent
│   ├── safety_agent.py          — Driver safety worker agent
│   └── guardrails.py            — Input validation and PII enforcement node
├── lambda_src/
│   └── agent_handler.py         — Lambda entry point. Graph compiled once at init.
├── mcp_client/
│   └── agent.py                 — MCP client. Holds all server sessions open for agent lifetime.
├── mcp_servers/
│   ├── fleet_query/             — Fleet status MCP server
│   ├── maintenance/             — Maintenance records MCP server
│   └── alert_dispatch/          — Alert dispatch MCP server. Severity-gated.
├── state/
│   ├── incident_state.py        — Incident state schema (truck_id, fault_code, severity, escalate)
│   └── orchestrator_state.py    — Orchestrator state schema (incident_type, routed_to, worker_result)
├── modules/
│   ├── agent-queue/             — SQS queue, DLQ, Lambda, IAM
│   └── bedrock-guardrail/       — Bedrock guardrail Terraform module
├── environments/
│   └── dev/                     — Dev environment Terraform root
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── locals.tf
│       └── versions.tf
├── tests/
│   ├── test_agent_integration.py — End-to-end agent flow tests
│   ├── test_guardrails.py        — PII and escalation boundary tests
│   ├── test_mcp_agent.py         — MCP tool loading and invocation tests
│   └── test_security.py          — IAM, encryption and data residency checks
├── requirements.txt             — Python dependencies (local and test)
├── requirements-lambda.txt      — Python dependencies (Lambda runtime)
└── build_lambda.sh              — Lambda zip package build script
```

---

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Python | 3.11 | Agent runtime and tests. 3.12+ has patchy support for LangGraph and MCP tooling. |
| Terraform | >= 1.6.0 | Infrastructure provisioning |
| AWS CLI | >= 2.0 | Deployment and manual invocation |
| Git Bash | any | Build script execution on Windows |

AWS prerequisites:
- IAM Identity Center configured with an SSO profile and sufficient permissions in the target account
- Terraform remote state S3 bucket provisioned in the management account (`trackhaul-terraform-state-{account_id}`)
- Terraform remote state DynamoDB lock table provisioned in the management account (`trackhaul-terraform-locks`)

---

## Usage

**1. Create and activate virtual environment on Python 3.11**
```bash
py -3.11 -m venv .venv
source .venv/Scripts/activate   # Git Bash on Windows
python --version                 # Must show 3.11.x
```

**2. Install dependencies**
```bash
pip install -r requirements.txt
```

**3. Build the Lambda package**
```bash
bash build_lambda.sh
```

**4. Authenticate to AWS**
```bash
aws sso login --profile <your-sso-profile>
aws sts get-caller-identity  # verify correct account
```

**5. Deploy infrastructure**
```bash
cd environments/dev
terraform init
terraform plan
terraform apply
```

**6. Run tests**
```bash
cd /c/files/nitya/workspace/trackhaul/trackhaul-agentic
python -m pytest tests/ -v
```

**7. Send a test incident via SQS**
```bash
QUEUE_URL=$(aws sqs get-queue-url \
  --queue-name trackhaul-dev-incident-agent \
  --region eu-central-1 \
  --query QueueUrl --output text)

aws sqs send-message \
  --queue-url $QUEUE_URL \
  --message-body '{"truck_id":"TH-1023","incident_type":"fault_code","fault_code":"P0300"}' \
  --region eu-central-1
```

**8. Invoke Lambda directly for testing**
```bash
aws lambda invoke \
  --function-name trackhaul-dev-agent-handler \
  --region eu-central-1 \
  --payload file://environments/dev/payload.json \
  --cli-binary-format raw-in-base64-out \
  response.json && cat response.json
```

---

## Security Considerations

**No PII in LLM prompts**
A dedicated guardrail validation node runs before any tool call or model invocation. The Bedrock Guardrail (`bedrock-guardrail` module) is applied to the raw user query — not the assembled prompt — to ensure PII entity classifiers match correctly against short, direct input. Driver names, addresses, phone numbers and driver IDs are blocked at the Lambda boundary. Truck IDs are the only vehicle identifiers that enter agent context.

**Bedrock Guardrail applied before retrieval**
The guardrail is not applied at the `invoke_model` call. It is applied to the raw incident payload at the validation node, before any MCP tool is called. Applying it inside the full assembled prompt causes the PII and topic classifiers to miss matches due to context dilution.

**EU data residency**
All Bedrock inference is scoped to `eu-central-1`. The Lambda execution role restricts `bedrock:InvokeModel` to EU ARNs only. No data leaves EU regions at any stage. This is enforced independently at the SCP level in the management account.

**Reserved concurrency as throttle**
Lambda reserved concurrency is set below the Bedrock RPM quota. This acts as a hard gate between the SQS burst and Bedrock, preventing quota exhaustion during fleet-wide incident storms.

**KMS customer managed key**
A dedicated CMK covers the agentic boundary — SQS messages and Lambda environment variables. Key rotation is enabled. The Lambda execution role is granted `kms:Decrypt` and `kms:GenerateDataKey` scoped to this key only.

**Least privilege IAM**
The Lambda execution role has separate inline policies per permission boundary: SQS receive and delete on the specific queue ARN, Bedrock invoke on EU ARNs, Bedrock guardrail application, and KMS decrypt on the agentic key. `AWSLambdaBasicExecutionRole` is the only managed policy attached.

**LangGraph graph compiled once at Lambda init**
`build_orchestrator()` is called at module level in `agent_handler.py`, outside the handler function. Lambda reuses the execution environment across warm invocations. Compiling the graph inside the handler would add 2–5 seconds of overhead to every invocation. Warm starts are effectively free.

