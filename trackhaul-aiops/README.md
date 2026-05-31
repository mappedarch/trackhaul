# TrackHaul — AIOps Anomaly Explainer

![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.6.0-623CE4?logo=terraform)
![AWS Provider](https://img.shields.io/badge/AWS%20Provider-~%3E5.0-FF9900?logo=amazon-aws)
![Python](https://img.shields.io/badge/Python-3.12-3776AB?logo=python)
![License](https://img.shields.io/badge/License-MIT-green)

An event-driven AIOps layer for the TrackHaul fleet intelligence platform. When a telemetry anomaly event is published to the EventBridge fleet event bus, a Lambda function invokes Amazon Bedrock to generate a structured natural language explanation — what happened, the likely cause, what similar past incidents indicate, and the recommended immediate action. Explanations are written to a structured CloudWatch log group with no PII.

The system sits on top of the Project 3 event-driven processing pipeline and consumes events from the same EventBridge custom bus. No additional event ingestion infrastructure is required.

All infrastructure is defined in Terraform using a modular structure. No manual console configuration is used.

---

## Architecture

```
EventBridge Custom Bus
trackhaul-dev-fleet-events
(from Project 3 — Event-Driven Pipeline)
        |
        | Event pattern match:
        | source: trackhaul.telemetry
        | detail-type: fuel_anomaly | engine_fault |
        |              harsh_braking | geofence_breach
        v
+------------------------------------------+
|   AIOps Explainer Lambda                 |
|   trackhaul-dev-aiops-explainer          |
|                                          |
|   1. Extract truck_id, event_type,       |
|      region, sensor_data from event      |
|   2. Build structured prompt             |
|      No PII — truck_id and sensor        |
|      readings only                       |
|   3. Invoke Amazon Bedrock               |
|      Claude Sonnet — EU cross-region     |
|      inference profile                   |
|   4. Parse structured JSON explanation   |
|   5. Write to CloudWatch log group       |
+--------+---------------------------------+
         |
         v
+------------------------------------------+
|   Amazon Bedrock                         |
|   eu.anthropic.claude-sonnet-4-5-...     |
|   Cross-region inference profile         |
|   Primary: eu-central-1                  |
|   Bedrock routes within EU only          |
+------------------------------------------+
         |
         v
+------------------------------------------+
|   CloudWatch Log Group                   |
|   /trackhaul/aiops/explainer/dev         |
|                                          |
|   Structured explanation log per event:  |
|   - truck_id                             |
|   - event_type                           |
|   - region                               |
|   - sensor_data                          |
|   - what_happened                        |
|   - likely_cause                         |
|   - similar_pattern                      |
|   - recommended_action                   |
|   - urgency                              |
+------------------------------------------+
```

**Primary region:** eu-central-1
**Bedrock model:** Claude Sonnet via EU cross-region inference profile
**Encryption:** IAM-scoped to inference profile and EU foundation model ARNs only
**No PII in any prompt or log** — truck IDs and sensor readings only

---

## Explanation Output Schema

For every anomaly event, the Lambda returns and logs a structured JSON explanation in this exact format:

```json
{
  "what_happened": "Fuel consumption exceeded the expected threshold by 38% over a 4-hour window.",
  "likely_cause": "Sensor readings indicate engine load anomaly consistent with injector fault or fuel system leak.",
  "similar_pattern": "Similar fuel anomaly patterns in the Poland region have previously indicated injector fouling requiring scheduled maintenance.",
  "recommended_action": "Schedule diagnostic inspection within 24 hours and monitor fuel delta readings on the next two trips.",
  "urgency": "high"
}
```

Valid values for `urgency`: `low`, `medium`, `high`, `critical`.

---

## Event Pattern

The EventBridge rule matches events on the `trackhaul-dev-fleet-events` bus with the following pattern:

```json
{
  "source": ["trackhaul.telemetry"],
  "detail-type": ["fuel_anomaly", "engine_fault", "harsh_braking", "geofence_breach"]
}
```

The expected event detail shape consumed by the Lambda:

```json
{
  "truck_id": "TH-4821",
  "event_type": "fuel_anomaly",
  "region": "PL",
  "timestamp": "2025-09-29T08:14:00Z",
  "sensor_data": {
    "fuel_delta_litres": 45.2,
    "engine_load_pct": 87,
    "speed_kmh": 94
  }
}
```

No driver names, GPS coordinates, or personal identifiers are permitted in any event payload.

---

## Module Reference

| Module | Path | Description |
|---|---|---|
| `aiops_explainer` | `modules/aiops_explainer` | Lambda function, IAM execution role, EventBridge rule and target, Lambda permission for EventBridge invocation, and two CloudWatch log groups with explicit retention. All resources named with environment prefix. |

---

## Repository Structure

```
trackhaul-aiops/
├── environments/
│   └── dev/
│       ├── locals.tf               - Naming prefix and log retention locals
│       ├── main.tf                 - Module orchestration
│       ├── outputs.tf              - Function name, ARN, log group name
│       ├── variables.tf            - Variable declarations
│       ├── versions.tf             - Provider, backend, and default tags
│       └── terraform.tfvars        - Variable values (not committed)
├── lambda_src/
│   └── aiops_explainer/
│       └── handler.py              - Explainer Lambda — prompt build, Bedrock invoke, log write
└── modules/
    └── aiops_explainer/
        ├── main.tf                 - All module resources
        ├── outputs.tf              - Function name, ARN, log group name
        └── variables.tf            - Variable declarations with defaults
```

---

## Prerequisites

### Tools

| Tool | Version | Purpose |
|---|---|---|
| Terraform | >= 1.6.0 | Infrastructure provisioning |
| AWS CLI | >= 2.13 | Authentication and CLI operations |
| Python | >= 3.12 | Lambda runtime |
| Git | Any | Version control |

### AWS Prerequisites

- IAM Identity Center configured with an SSO profile and sufficient permissions in the target account
- Terraform remote state S3 bucket and DynamoDB lock table provisioned in the management account (see Project 1)
- Project 3 (Event-Driven Pipeline) deployed — the EventBridge custom bus `trackhaul-dev-fleet-events` must exist before this project is applied
- Amazon Bedrock model access enabled for `anthropic.claude-sonnet-4-5-20250929-v1:0` in `eu-central-1`

### Bedrock Cross-Region Inference Profile

The Lambda uses the EU cross-region inference profile `eu.anthropic.claude-sonnet-4-5-20250929-v1:0`. This profile allows Bedrock to route requests within the EU region group (eu-central-1, eu-west-1, eu-north-1) for availability. All routing stays within the EU — GDPR data residency is not affected.

The IAM policy scopes Bedrock access to both the inference profile ARN and the underlying foundation model ARNs across EU regions. Both are required — the inference profile ARN alone is insufficient for `bedrock:InvokeModel`.

---

## Usage

### 1. Authenticate

```bash
aws sso login --profile <your-sso-profile>
aws sts get-caller-identity
```

### 2. Verify Project 3 event bus exists

```bash
aws events describe-event-bus \
  --name trackhaul-dev-fleet-events \
  --region eu-central-1
```

This must return successfully before applying this project.

### 3. Configure variables

```bash
cd environments/dev
```

Edit `terraform.tfvars` and set:

```hcl
aws_region       = "eu-central-1"
environment      = "dev"
aws_account_id   = "<your-account-id>"
event_bus_name   = "trackhaul-dev-fleet-events"
bedrock_region   = "eu-central-1"
bedrock_model_id = "eu.anthropic.claude-sonnet-4-5-20250929-v1:0"
```

### 4. Initialise Terraform

```bash
terraform init
```

### 5. Plan and apply

```bash
terraform plan
terraform apply
```

### 6. Send a test anomaly event

```bash
aws events put-events --entries '[
  {
    "Source": "trackhaul.telemetry",
    "DetailType": "fuel_anomaly",
    "Detail": "{\"truck_id\": \"TH-4821\", \"event_type\": \"fuel_anomaly\", \"region\": \"PL\", \"timestamp\": \"2025-09-29T08:14:00Z\", \"sensor_data\": {\"fuel_delta_litres\": 45.2, \"engine_load_pct\": 87, \"speed_kmh\": 94}}",
    "EventBusName": "trackhaul-dev-fleet-events"
  }
]' --region eu-central-1
```

### 7. Verify the explanation was generated

```bash
# Check Lambda execution logs
aws logs tail /aws/lambda/trackhaul-dev-aiops-explainer \
  --since 5m \
  --region eu-central-1

# Check structured explanation log
aws logs tail /trackhaul/aiops/explainer/dev \
  --since 5m \
  --region eu-central-1
```

The explanation log entry will contain the full structured JSON output including `what_happened`, `likely_cause`, `similar_pattern`, `recommended_action`, and `urgency`.

---

## Security Considerations

**IAM scoped to inference profile and EU foundation model ARNs**
The Lambda execution role policy grants `bedrock:InvokeModel` on two resource ARNs: the EU cross-region inference profile ARN (account-scoped) and the foundation model ARN with a wildcard region (`arn:aws:bedrock:*::foundation-model/...`). The wildcard region is required because the cross-region profile may route to any EU region. The policy does not grant access to any other model or any non-Bedrock service beyond what the Lambda requires.

**No PII in prompts or logs**
The `build_prompt` function constructs the Bedrock prompt from `truck_id`, `event_type`, `region`, `timestamp`, and `sensor_data` only. Driver names, GPS coordinates, and route identifiers are not present in the event detail schema and do not enter the prompt. The `log_explanation` function writes only the same fields to CloudWatch.

**Two CloudWatch log groups with explicit retention**
Two log groups are created: the custom explanation log group `/trackhaul/aiops/explainer/{env}` and the Lambda default log group `/aws/lambda/trackhaul-{env}-aiops-explainer`. Both are created in Terraform with explicit retention before the Lambda is deployed. Without pre-creating the Lambda default log group, Lambda silently fails to write logs if it cannot create the group itself due to IAM restrictions.

**Least privilege IAM**
The execution role has three inline policies: CloudWatch Logs write access scoped to both log group ARNs, `bedrock:InvokeModel` scoped to the inference profile and EU foundation model ARNs, and no other permissions. The role cannot read SSM, write to S3, or access any other service.

**EventBridge source and detail-type filtering**
The EventBridge rule matches on both `source` and `detail-type`. Matching on `detail-type` alone would trigger the Lambda on any event with a matching type from any source on the bus. The `source: trackhaul.telemetry` condition restricts invocations to telemetry events only.

**Remote state isolation**
The Terraform state for this project is stored at key `trackhaul-aiops/dev/terraform.tfstate` — separate from all other projects. A destructive operation in this project cannot affect the state of the event pipeline, the AI layer, or the landing zone.

---

## Lessons Learned

**Bedrock cross-region inference profile requires both the profile ARN and the foundation model ARN in the IAM policy**
The inference profile ARN is account-scoped (`arn:aws:bedrock:{region}:{account}:inference-profile/...`). The foundation model ARN is not account-scoped (`arn:aws:bedrock:*::foundation-model/...`). Granting only the inference profile ARN produces an `AccessDeniedException` at runtime because Bedrock resolves the underlying model during routing and checks the foundation model ARN separately. Both must be present in the `Resource` list.

**Lambda default log group must be created before the function — not after**
If the Lambda execution role does not have `logs:CreateLogGroup`, the function silently loses all runtime logs on first invocation because it cannot create its own log group. Creating the log group explicitly in Terraform before the function is deployed, and scoping the IAM policy to that ARN, avoids this. The `depends_on` block in the Lambda resource enforces the creation order.

**EventBridge custom bus rules require `event_bus_name` on both the rule and the target**
Setting `event_bus_name` on `aws_cloudwatch_event_rule` alone is not sufficient. The `aws_cloudwatch_event_target` resource also requires `event_bus_name` to be set explicitly. Omitting it from the target causes Terraform to associate the target with the default event bus, not the custom bus. The rule and target exist but the Lambda is never invoked.

**Bedrock response may include markdown code fences despite JSON-only instructions**
The prompt instructs the model to return only a JSON object with no markdown. In practice, responses occasionally include triple-backtick code fences wrapping the JSON. The handler strips these with a regex before parsing. Without this, `json.loads` raises a parse error on otherwise valid responses and the Lambda fails with a non-retryable error.

**Lambda timeout must account for Bedrock cold model latency — 30 seconds minimum**
The default Lambda timeout of 3 seconds is insufficient for Bedrock invocations. At low traffic volumes, model cold start latency can exceed 10 seconds. The Lambda is configured with a 30-second timeout. In production at high event volume, P99 latency should be measured and the timeout adjusted accordingly. A timeout that is too short causes retries from EventBridge, which can result in duplicate explanations for the same anomaly event.
