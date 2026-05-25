# TrackHaul — Real-Time Streaming Telemetry

![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.6.0-623CE4?logo=terraform)
![AWS Provider](https://img.shields.io/badge/AWS%20Provider-~%3E5.0-FF9900?logo=amazon-aws)
![License](https://img.shields.io/badge/License-MIT-green)

A GDPR-compliant real-time telemetry streaming pipeline built on AWS. Vehicle telemetry is ingested into Kinesis Data Streams, consumed by a Lambda Enhanced Fan-Out consumer, and delivered to an S3 data lake in Parquet format via Firehose. Anomaly events are forwarded to EventBridge for downstream processing. All data at rest and in transit is encrypted with KMS customer managed keys. No PII enters any payload.

---

## Architecture

```
Vehicle Telemetry Source (trucks, simulators, test scripts)
        |
        v
+------------------------------------------+
|   Kinesis Data Stream                    |
|   trackhaul-telemetry-{env}             |
|   4 shards, KMS encrypted (CMK)         |
|   Retention: 7 days                     |
+----------+-------------------------------+
           |
     +-----+-----+
     |             |
     v             v
+--------------------+   +------------------------------------------+
|  Lambda EFO        |   |  Firehose Delivery Stream                |
|  Consumer          |   |  trackhaul-telemetry-{env}               |
|  trackhaul-        |   |  Source: Kinesis Data Stream             |
|  telemetry-        |   |  Buffer: 128MB / 5 min                   |
|  consumer-{env}    |   |  Parquet conversion via Glue schema      |
|  2x parallelism    |   |  SNAPPY compression                      |
|  DLQ on failure    |   |  KMS encrypted (CMK)                     |
|  KMS encrypted     |   +------------------+-----------------------+
+----+---------------+                      |
     |                                      v
     v                        +-------------------------------+
+--------------------+        |  S3 Data Lake                 |
|  EventBridge       |        |  trackhaul-telemetry-         |
|  Custom Bus        |        |  datalake-{account}-{env}     |
|  trackhaul-        |        |  telemetry/year=/month=/day=  |
|  fleet-events      |        |  errors/year=/month=/day=     |
|  (anomalies only)  |        |  KMS encrypted (CMK)          |
+--------------------+        |  Versioning enabled           |
                              |  Lifecycle:                   |
                              |    IA at 30 days              |
                              |    Glacier at 90 days         |
                              |    Delete at 365 days (GDPR)  |
                              +---------------+---------------+
                                              |
                              +---------------+---------------+
                              |  Glue Data Catalog            |
                              |  DB: trackhaul_telemetry_{env}|
                              |  Table: fleet_telemetry       |
                              |  Format: Parquet              |
                              +-------------------------------+

Primary region: eu-central-1
Two KMS CMKs — one for Kinesis stream, one for S3 and Firehose
No PII in any payload — truck IDs only
```

---

## Telemetry Payload Schema

All records follow this structure. No driver names, GPS coordinates, or personal identifiers are included in any payload.

```json
{
  "truck_id": "TH-4821",
  "event_type": "fuel_anomaly",
  "fuel_level": 12,
  "speed_kmh": 87,
  "engine_temp": 104,
  "timestamp": "2026-05-25T10:00:00Z",
  "region": "DE"
}
```

Anomaly event types forwarded to EventBridge:

| Event Type | Description |
|---|---|
| `fuel_anomaly` | Abnormal fuel consumption or critically low fuel level |
| `engine_fault` | Engine fault code detected |
| `harsh_braking` | Harsh braking event exceeding threshold |
| `geofence_breach` | Vehicle outside authorised operating zone |

---

## Module Reference

| Module | Path | Description |
|---|---|---|
| `kms` | `modules/kms` | Two CMKs — one for Kinesis, one for S3 and Firehose. Key rotation enabled. Least-privilege key policy per service principal and IAM role. ARN published to SSM Parameter Store. |
| `kinesis` | `modules/kinesis` | Kinesis Data Stream with 4 provisioned shards, 7-day retention, KMS encryption, and shard-level CloudWatch metrics for hot shard detection. |
| `kinesis_consumer` | `modules/kinesis_consumer` | Lambda EFO consumer registered against the Kinesis stream. Enhanced Fan-Out provides dedicated 2MB/s throughput per shard. Parallelisation factor of 2. DLQ for failed batches. ReportBatchItemFailures enabled. Bisect-on-error enabled to isolate bad records. |
| `firehose` | `modules/firehose` | Firehose delivery stream sourced from Kinesis. Converts JSON to Parquet via Glue schema with SNAPPY compression. Buffers at 128MB or 5 minutes. Separate error prefix for malformed records. CloudWatch delivery error logging enabled. |
| `glue` | `modules/glue` | Glue Data Catalog database and table defining the fleet telemetry schema. Used by Firehose for Parquet serialisation. |
| `s3_datalake` | `modules/s3_datalake` | S3 data lake bucket with KMS encryption, versioning, and full public access block. Lifecycle policy tiers telemetry to IA at 30 days, Glacier at 90 days, and deletes at 365 days to satisfy GDPR retention limits. Error objects purged after 30 days. |

---

## Repository Structure

```
trackhaul-streaming/
├── environments/
│   └── dev/
│       ├── main.tf           - Module orchestration for dev environment
│       └── variables.tf      - Variable declarations and defaults
├── lambda_src/
│   └── telemetry_consumer/
│       ├── handler.py        - EFO consumer — decodes, parses, forwards anomalies
│       └── telemetry_consumer.zip
└── modules/
    ├── kms/                  - Customer managed keys
    ├── kinesis/              - Kinesis Data Stream
    ├── kinesis_consumer/     - Lambda EFO consumer, DLQ, event source mapping
    ├── firehose/             - Firehose delivery stream and IAM role
    ├── glue/                 - Glue Data Catalog database and table
    └── s3_datalake/          - S3 bucket, encryption, lifecycle policy
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
- Terraform remote state S3 bucket and DynamoDB lock table provisioned in the management account
- Lambda deployment package zipped and present at `lambda_src/telemetry_consumer/telemetry_consumer.zip`

---

## Usage

### 1. Authenticate

```bash
aws sso login --profile <your-sso-profile>

# Verify the correct account is active
aws sts get-caller-identity
```

### 2. Zip the Lambda deployment package

```bash
cd lambda_src/telemetry_consumer
zip telemetry_consumer.zip handler.py
cd ../..
```

### 3. Configure variables

```bash
cd environments/dev

cat > terraform.tfvars << EOF
aws_account_id = "<your-account-id>"
EOF
```

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

### 7. Send a test record

```python
import boto3, json

client = boto3.client('kinesis', region_name='eu-central-1')

payload = {
    'truck_id': 'TH-4821',
    'event_type': 'fuel_anomaly',
    'fuel_level': 12,
    'speed_kmh': 87,
    'engine_temp': 104,
    'timestamp': '2026-05-25T10:00:00Z',
    'region': 'DE'
}

response = client.put_record(
    StreamName='trackhaul-telemetry-dev',
    Data=json.dumps(payload).encode('utf-8'),
    PartitionKey='TH-4821'
)
print(response)
```

> Note: Always use the boto3 SDK or encode payloads as valid UTF-8 before calling `put-record` via the AWS CLI. The CLI `--data` flag does not encode automatically and will produce malformed records that fail Lambda decoding.

### 8. Verify processing

```bash
# Check Lambda processed the record
LOG_GROUP='/aws/lambda/trackhaul-telemetry-consumer-dev'
aws logs filter-log-events \
  --log-group-name "$LOG_GROUP" \
  --region eu-central-1 \
  --start-time $(date -d '5 minutes ago' +%s000)

# Confirm Parquet files landing in S3
aws s3 ls s3://trackhaul-telemetry-datalake-<account-id>-dev/ \
  --recursive \
  --region eu-central-1
```

---

## Security Considerations

**Two KMS customer managed keys**
Separate CMKs are used for the Kinesis stream and the S3/Firehose layer. This enforces a data classification boundary — access to S3 data does not imply access to stream data. Both keys have rotation enabled. AWS-managed SSE is not used on any resource.

**KMS key policy — two-sided permission model**
Both the IAM role policy and the KMS key policy must explicitly allow decrypt access. Either side alone produces an access denied error. Lambda, Firehose, and Kinesis service principals are each granted only the actions they require — no wildcard actions in key policies.

**No PII in any payload**
All telemetry payloads carry truck IDs only. Driver names, GPS coordinates, and personal identifiers are excluded at the schema level. The Lambda consumer logs truck ID and event type only. EventBridge entries carry no PII.

**Least privilege IAM**
The Lambda execution role is scoped to the specific Kinesis stream ARN, its own CloudWatch log group, the KMS key ARN, and the DLQ ARN. The Firehose IAM role is scoped to the source stream ARN, the destination bucket ARN, and the two KMS key ARNs.

**DLQ on Lambda consumer**
Failed record batches are routed to a dedicated SQS DLQ after exhausting retries. Bisect-on-error is enabled, which halves the batch on each failure to isolate the offending record. This prevents a single malformed record from blocking the entire shard indefinitely.

**S3 data lake access controls**
All public access is blocked at the bucket level. Versioning is enabled. Server-side encryption uses a CMK with bucket key enabled to reduce KMS API call volume at high throughput.

**GDPR retention enforcement**
S3 lifecycle policy hard-deletes telemetry objects after 365 days. Error objects are purged after 30 days. No manual intervention is required for data deletion compliance.

---

## Gotchas and Lessons Learned

**KMS key policy and IAM role policy are both required**
Lambda's IAM role policy must allow `kms:Decrypt` and `kms:GenerateDataKey`, and the KMS key policy must also explicitly list the Lambda role ARN. Either side alone produces an access denied error at runtime. The error message does not clearly identify which side is missing — always verify both.

**Circular dependency — KMS key policy requires Lambda role ARN**
The Kinesis KMS key policy requires the Lambda execution role ARN to grant decrypt access. If the KMS module depends on the kinesis_consumer module output and kinesis_consumer depends on the KMS module output, Terraform raises a circular dependency error. This is resolved by constructing the role ARN from the naming convention in a locals block in the environment `main.tf` and passing it directly into the KMS module.

**AWS CLI `--data` flag does not base64-encode automatically on Windows**
On Windows with Git Bash, the `--data` flag in `aws kinesis put-record` does not produce valid base64. Records arrive in the stream as raw bytes. Lambda's `base64.b64decode()` then fails with a UnicodeDecodeError. Always use the boto3 SDK or a Python script to send test records.

**EFO retry loop with infinite `MaximumRetryAttempts`**
The default `MaximumRetryAttempts: -1` (infinite) combined with `BisectBatchOnFunctionError: true` causes Lambda to retry malformed records indefinitely, blocking the shard. In production, set `MaximumRetryAttempts` and `MaximumRecordAgeInSeconds` to finite values. To recover from a stuck shard in development, delete and recreate the event source mapping with `StartingPosition: AT_TIMESTAMP` set to the current time.

**Firehose Parquet conversion requires Glue schema to match payload exactly**
If the Glue table schema does not match the incoming JSON field names and types, Firehose routes records to the error prefix silently. No alarm fires by default. Always validate the Glue schema against the actual payload schema before testing Firehose delivery.

**Firehose KMS access — two keys required**
Firehose requires decrypt access to the Kinesis KMS key to read from the stream, and generate-data-key access to the S3 KMS key to write to the bucket. Both key policies must explicitly allow the Firehose IAM role ARN. Missing either produces a silent delivery failure visible only in Firehose CloudWatch error logs.

**Iterator age spike on Lambda cold start**
After a Lambda cold start or EFO consumer restart, iterator age spikes as Lambda catches up on buffered records. A spike alone does not indicate a problem. Monitor iterator age in combination with error rate — a spike with no errors is a normal catch-up pattern. A spike with errors indicates a processing failure.

**Region drift between environments**
The dev environment deployed to eu-central-1 (DR region). The production target is eu-west-1 (primary region). Explicit region enforcement per environment should be applied via SCPs and environment-level variable files to prevent accidental cross-region deployment.
```
