# TrackHaul — Event-Driven Fleet Processing Pipeline

![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.6.0-623CE4?logo=terraform)
![AWS Provider](https://img.shields.io/badge/AWS%20Provider-~%3E5.0-FF9900?logo=amazon-aws)
![License](https://img.shields.io/badge/License-MIT-green)

A GDPR-compliant, event-driven fleet processing pipeline built on AWS. Vehicle telemetry events are routed through a custom EventBridge bus to four specialised Lambda consumers via SQS queues. Critical incidents are orchestrated through Step Functions. All data at rest is encrypted with a KMS customer managed key. No PII enters any event payload.

---

## Architecture

```
Vehicle Event Source
        |
        v
+-------------------------------+
|   EventBridge Custom Bus      |
|   trackhaul-{env}-fleet-events|
|   Source: trackhaul.fleet     |
+----------+--------------------+
           |  Rules - one per event type
     +-----+------+-------------+-----------------+
     v            v             v                 v
GEOFENCE_    FUEL_ANOMALY  DRIVER_SCORE_UPDATE  MAINTENANCE_
BREACH                                          REQUIRED
     |            |             |                 |
     v            v             v                 v
+---------+ +----------+ +------------+ +-------------+
|   SQS   | |   SQS    | |    SQS     | |     SQS     |
|  + DLQ  | |  + DLQ   | |   + DLQ   | |    + DLQ    |
+----+----+ +----+-----+ +-----+------+ +------+------+
     |            |             |                 |
     v            v             v                 v
+---------+ +----------+ +------------+ +-------------+
| Lambda  | |  Lambda  | |   Lambda   | |   Lambda    |
|geofence | |  fuel_   | |  driver_   | | maintenance |
|         | | anomaly  | |  scoring   | |             |
+----+----+ +----------+ +------------+ +------+------+
     |                                          |
     +------------------+------------------------+
                        v
           +---------------------------+
           |   Step Functions          |
           |   Incident Workflow       |
           |   (STANDARD type)         |
           +-------------+-------------+
                         |
               +---------+-----------+
               v                     v
         SNS Critical           SNS Maintenance
         Alerts Topic           Alerts Topic
```

**Primary region:** eu-central-1
**Encryption:** KMS customer managed key across all services
**No PII in any event payload** - truck IDs only

---

## Event Types

| Event Type | Source | Consumer | Triggers Incident Workflow |
|---|---|---|---|
| `GEOFENCE_BREACH` | `trackhaul.fleet` | geofence | Yes |
| `FUEL_ANOMALY` | `trackhaul.fleet` | fuel_anomaly | No |
| `DRIVER_SCORE_UPDATE` | `trackhaul.fleet` | driver_scoring | No |
| `MAINTENANCE_REQUIRED` | `trackhaul.fleet` | maintenance | Yes |

---

## Event Payload Schema

All events follow this structure. No driver names, GPS coordinates, or personal identifiers are included in any payload.

```json
{
  "source": "trackhaul.fleet",
  "detail-type": "FUEL_ANOMALY",
  "detail": {
    "truck_id": "TH-4821",
    "anomaly_type": "EXCESS_CONSUMPTION",
    "fuel_delta_litres": 45.2,
    "region": "PL",
    "severity": "HIGH"
  }
}
```

---

## Module Reference

| Module | Path | Description |
|---|---|---|
| `kms` | `modules/kms` | Customer managed key for SQS, SNS, Lambda, and CloudWatch Logs encryption. Key rotation enabled. Least-privilege key policy per service principal. |
| `eventbridge` | `modules/eventbridge` | Custom event bus, four routing rules, IAM role for SQS delivery, schema registry and discoverer, 90-day event archive. |
| `sqs` | `modules/sqs` | One main queue and one DLQ per consumer. CMK encrypted. Redrive policy after 3 failures. CloudWatch alarm on DLQ depth. |
| `lambda-consumers` | `modules/lambda-consumers` | Four Lambda functions in Python 3.12. ReportBatchItemFailures enabled. One scoped IAM execution role per function. |
| `step-functions` | `modules/step-functions` | STANDARD type state machine for incident orchestration. Full execution history. CloudWatch logging and X-Ray tracing enabled. |
| `sns` | `modules/sns` | Two CMK-encrypted topics - critical alerts and maintenance alerts. Publish policy locked to Step Functions service principal with source account condition. |

---

## Repository Structure

```
trackhaul-event-pipeline/
├── environments/
│   └── dev/
│       ├── main.tf           - Module orchestration for dev environment
│       ├── variables.tf      - Variable declarations
│       ├── outputs.tf        - Environment outputs
│       ├── backend.tf        - Remote state configuration
│       └── terraform.tfvars  - Variable values (not committed)
├── lambda_src/
│   ├── geofence/
│   │   └── handler.py        - Geofence breach consumer
│   ├── fuel_anomaly/
│   │   └── handler.py        - Fuel anomaly consumer
│   ├── driver_scoring/
│   │   └── handler.py        - Driver scoring consumer
│   └── maintenance/
│       └── handler.py        - Maintenance event consumer
└── modules/
    ├── kms/                  - Customer managed key
    ├── eventbridge/          - Custom bus, rules, schema registry
    ├── sqs/                  - Queue, DLQ, CloudWatch alarm
    ├── lambda-consumers/     - Four consumer functions and IAM roles
    ├── step-functions/       - Incident orchestration state machine
    └── sns/                  - Alert topics
```

---

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Terraform | >= 1.6.0 | Infrastructure provisioning |
| AWS CLI | >= 2.13 | Authentication and CLI operations |
| Python | >= 3.12 | Lambda function runtime |
| Git | Any | Version control |

AWS prerequisites:
- IAM Identity Center configured with an SSO profile and sufficient permissions in the target account
- Terraform remote state S3 bucket provisioned in the management account
- Terraform remote state DynamoDB lock table provisioned in the management account

---

## Usage

### 1. Authenticate

```bash
aws sso login --profile <your-sso-profile>

# Verify the correct account is active
aws sts get-caller-identity
```

### 2. Configure variables

```bash
cd environments/dev

cat > terraform.tfvars << EOF
project        = "trackhaul"
environment    = "dev"
aws_region     = "eu-central-1"
aws_account_id = "<your-account-id>"
ops_email      = "<your-ops-email>"
EOF
```

### 3. Update backend configuration

Edit `environments/dev/backend.tf` and set the S3 bucket name and DynamoDB lock table name to match the remote state resources in the management account.

### 4. Initialise Terraform

```bash
cd environments/dev
terraform init
```

### 5. Plan

```bash
terraform plan
```

### 6. Apply

```bash
terraform apply
```

### 7. Send a test event

```bash
aws events put-events --entries '[
  {
    "Source": "trackhaul.fleet",
    "DetailType": "FUEL_ANOMALY",
    "Detail": "{\"truck_id\": \"TH-4821\", \"anomaly_type\": \"EXCESS_CONSUMPTION\", \"fuel_delta_litres\": 45.2, \"region\": \"PL\", \"severity\": \"HIGH\"}",
    "EventBusName": "trackhaul-dev-fleet-events"
  }
]'
```

### 8. Verify processing

```bash
# Check Lambda logs
aws logs tail /aws/lambda/trackhaul-dev-fuel_anomaly --since 5m

# Confirm DLQ is empty
aws sqs get-queue-attributes \
  --queue-url $(aws sqs get-queue-url --queue-name trackhaul-fuel_anomaly-dlq-dev --query QueueUrl --output text) \
  --attribute-names ApproximateNumberOfMessages
```

---

## Security Considerations

**KMS customer managed key**
A single CMK covers SQS, SNS, Lambda environment variables, and CloudWatch Logs. The key policy grants permissions per service using least-privilege statements - no wildcard principals. Key rotation is enabled. AWS-managed SSE is not used on any resource.

**No PII in event payloads**
All event payloads carry truck IDs only. Driver names, GPS coordinates, and personal identifiers are excluded at the schema level. Lambda consumers log truck IDs and event metadata only.

**Least privilege IAM**
Each Lambda consumer has its own execution role. Policies are scoped to the specific SQS queue ARN, the function's CloudWatch log group, the KMS key ARN, and the Step Functions state machine ARN. No shared roles between consumers.

**DLQ on every queue**
Every SQS queue has a dedicated DLQ with a CloudWatch alarm. Messages that fail processing three times are moved to the DLQ and an alarm fires immediately. This prevents silent message loss.

**EventBridge source locking**
All EventBridge rules match on `source: trackhaul.fleet` in addition to `detail-type`. This prevents accidental rule matches from other event sources sharing the same bus.

**Step Functions STANDARD type**
The incident workflow uses STANDARD execution type, which provides exactly-once execution semantics and a full, queryable execution history. This is required for GDPR audit traceability.

**SNS topic policies**
Both SNS topics restrict publish access to the Step Functions service principal with an `aws:SourceAccount` condition. Cross-account publish is not permitted.

---

## Gotchas and Lessons Learned

**KMS and CloudWatch Logs - encryption context condition is mandatory**
CloudWatch Logs enforces a strict encryption context when calling `kms:GenerateDataKey`. The key policy must include a `kms:EncryptionContext:aws:logs:arn` condition scoped to the account and region. Without this, log group encryption applies in Terraform but log delivery silently fails at runtime - no error is surfaced in the console.

**SQS CMK - EventBridge delivery requires explicit key policy entry**
When SQS queues are encrypted with a CMK, EventBridge cannot deliver messages unless the KMS key policy explicitly allows `kms:GenerateDataKey` for the `sqs.amazonaws.com` service principal. The SQS queue resource policy alone is not sufficient.

**Lambda KMS decrypt - two-sided permission model**
The Lambda execution role policy must allow `kms:Decrypt` and `kms:GenerateDataKey`, and the KMS key policy must also explicitly allow the role ARN. Either side alone produces an access denied error. The error message does not clearly identify which side is missing.

**ReportBatchItemFailures - must be declared on the event source mapping**
Partial batch failure support requires `function_response_types = ["ReportBatchItemFailures"]` on the `aws_lambda_event_source_mapping` resource. Without this, a single failed message causes the entire batch to retry, leading to duplicate processing of messages that succeeded.

**Step Functions include_execution_data - production risk**
Setting `include_execution_data = true` captures full state input and output into CloudWatch Logs. This is acceptable in development for debugging. In production this must be set to `false` - at high event volume, state input captured in logs creates both a cost and a potential data exposure risk.

**Circular dependency - KMS key policy and Lambda role ARNs**
The KMS key policy requires Lambda execution role ARNs to grant decrypt access. If the KMS module depends on lambda-consumers outputs and lambda-consumers depends on KMS outputs, Terraform raises a circular dependency error. This is resolved by constructing Lambda role ARNs from the naming convention in a locals block in the environment main.tf and passing them directly into the KMS module - no cross-module dependency is created.

**EventBridge archive cost at scale**
The EventBridge archive retains all events without an event pattern filter. At peak throughput this generates significant storage volume. In production, the archive should be filtered to critical event types only, or replaced with a Firehose delivery to S3 for cost-effective long-term retention.
