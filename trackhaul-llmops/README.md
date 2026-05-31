# TrackHaul — LLMOps and Observability

![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.6.0-623CE4?logo=terraform)
![AWS Provider](https://img.shields.io/badge/AWS%20Provider-~%3E5.0-FF9900?logo=amazon-aws)
![Python](https://img.shields.io/badge/Python-3.12-3776AB?logo=python)
![License](https://img.shields.io/badge/License-MIT-green)

A production-grade LLMOps layer built on AWS for the TrackHaul fleet intelligence platform. All Bedrock invocations pass through a single instrumented Lambda wrapper that emits structured CloudWatch metrics, enforces GDPR controls, and writes interaction logs with no PII. Prompt versions are stored and governed in SSM Parameter Store. A daily drift detector runs statistical checks on response length across all query types. A feedback loop captures dispatcher corrections and reingests approved records into the golden dataset. An offline evaluation runner scores prompt responses against the golden dataset using three methods: exact match, embedding similarity, and LLM-as-judge.

All infrastructure is defined in Terraform using a modular structure. No manual console configuration is used.

---

## Architecture

```
Dispatcher Query
      |
      v
+------------------------------------------+
|   Lambda Bedrock Wrapper                 |
|   trackhaul-llm-wrapper-dev              |
|                                          |
|   1. Fetch active prompt — SSM via       |
|      Parameters & Secrets Extension      |
|   2. Call Bedrock InvokeModel            |
|   3. Emit Tier 1 operational metrics     |
|      TrackHaul/LLMOps namespace          |
|   4. Emit Tier 2 cost metrics            |
|      TrackHaul/LLMCost namespace         |
|   5. Write structured interaction log    |
|      /trackhaul/llm/interactions/{env}   |
+--------+---------------------------------+
         |
         v
+---------------------------+     +-------------------------------+
|   Amazon Bedrock          |     |   SSM Parameter Store         |
|   Claude Sonnet           |     |                               |
|   eu-central-1 (primary)  |     |   /trackhaul/llmops/prompts/  |
|   eu-west-1 (fallback)    |     |   fleet-assistant/v1          |
+---------------------------+     |   fleet-assistant/active      |
                                  +-------------------------------+

+------------------------------------------+
|   Drift Detector                         |
|   EventBridge Scheduler — daily 06:00 UTC|
|                                          |
|   Reads ResponseLengthMean from          |
|   CloudWatch (14-day window)             |
|   2 std dev threshold per query type     |
|   Consecutive counter in SSM             |
|   SNS alert after 3 consecutive days     |
+------------------------------------------+

+------------------------------------------+
|   Feedback Loop                          |
|                                          |
|   feedback_capture Lambda                |
|   Writes dispatcher ratings → DynamoDB   |
|                                          |
|   feedback_reingest Lambda               |
|   Approved corrections → S3 golden       |
|   dataset (new versioned JSONL)          |
+------------------------------------------+

+------------------------------------------+
|   Eval Framework                         |
|                                          |
|   S3 bucket — golden dataset + results   |
|   scripts/eval_runner.py                 |
|   Three scoring methods:                 |
|   - Exact match (structured fields)      |
|   - Embedding similarity (cosine 0.85)   |
|   - LLM-as-judge (20% sample)            |
|   Results written to S3 per run          |
+------------------------------------------+
```

**Primary region:** eu-central-1
**Bedrock fallback region:** eu-west-1
**Encryption:** KMS customer managed key across SSM, CloudWatch Logs, DynamoDB, and S3
**No PII in any log, metric, or prompt** — truck IDs only

---

## Metrics

Metrics are organised into three tiers.

### Tier 1 — Operational (alarm on these)

Published to namespace `TrackHaul/LLMOps`.

| Metric | Dimensions | Alarm Threshold |
|---|---|---|
| `InvocationLatency` | `model_id`, `query_type` | P95 > 3000ms, P99 > 5000ms |
| `InvocationErrorCount` | `model_id` | > 2% over 5 min |
| `ThrottledRequestCount` | `model_id` | > 0 |
| `InputTokensPerRequest` | `model_id`, `query_type` | > 4000 |
| `InvocationsTotal` | `model_id`, `query_type` | — |

### Tier 2 — Cost Governance (report and budget on these)

Published to namespace `TrackHaul/LLMCost`.

| Metric | Dimensions | Purpose |
|---|---|---|
| `InputTokensTotal` | `truck_id`, `model_id`, `fleet_region` | Per-vehicle input cost attribution |
| `OutputTokensTotal` | `truck_id`, `model_id`, `fleet_region` | Per-vehicle output cost attribution |
| `InvocationsTotal` | `query_type`, `fleet_region` | Volume baseline for capacity planning |

Input and output tokens are always separate dimensions. Bedrock prices them differently per model. A single TotalTokens metric is insufficient for accurate cost attribution and becomes misleading when models are switched.

### Tier 3 — Quality and Drift (trend over time)

Published to namespace `TrackHaul/LLMOps`.

| Metric | Dimensions | Purpose |
|---|---|---|
| `ResponseLengthMean` | `prompt_version`, `query_type` | Verbosity drift baseline |
| `DriftDetected` | `query_type`, `prompt_version` | 1 if drifted, 0 if stable |
| `ResponseLengthToday` | `query_type`, `prompt_version` | Today's value for dashboard comparison |
| `ResponseLengthBaseline` | `query_type`, `prompt_version` | Rolling baseline mean |

---

## Module Reference

| Module | Path | Description |
|---|---|---|
| `lambda-bedrock-wrapper` | `modules/lambda-bedrock-wrapper` | Single instrumentation point for all Bedrock invocations. Fetches active prompt via SSM extension cache, calls Bedrock, emits Tier 1 and Tier 2 metrics, writes structured interaction log. KMS-encrypted log group. |
| `prompt-store` | `modules/prompt-store` | SSM Parameter Store prompt governance. Stores versioned prompt text as `SecureString` encrypted with KMS. Maintains an `active` pointer that Lambda reads at invocation time. Rollback requires only an SSM update — no Lambda redeployment. |
| `drift-detector` | `modules/drift-detector` | Daily Lambda triggered by EventBridge Scheduler at 06:00 UTC. Reads 14 days of `ResponseLengthMean` from CloudWatch per query type. Applies 2 standard deviation threshold. Consecutive drift counter persisted in SSM. SNS alert published after 3 consecutive drifted days. |
| `eval-framework` | `modules/eval-framework` | S3 bucket for golden dataset and eval results. Versioning enabled. KMS-encrypted. Eval results transition to Glacier after 365 days. Golden dataset noncurrent versions move to Standard-IA after 90 days. |
| `feedback-loop` | `modules/feedback-loop` | DynamoDB table for dispatcher feedback records. Two Lambda functions: `feedback_capture` writes ratings to DynamoDB; `feedback_reingest` queries approved corrections via GSI and writes new golden dataset versions to S3. Point-in-time recovery enabled on DynamoDB. |

---

## Repository Structure

```
trackhaul-llmops/
├── docs/
│   └── llmops-strategy.md          - Full observability and governance strategy
├── environments/
│   └── dev/
│       ├── kms.tf                  - KMS CMK for LLMOps boundary
│       ├── locals.tf               - Naming prefix and shared locals
│       ├── main.tf                 - Module orchestration
│       ├── outputs.tf              - Environment outputs
│       ├── variables.tf            - Variable declarations
│       ├── versions.tf             - Provider and backend configuration
│       ├── terraform.tfvars        - Variable values (not committed)
│       ├── terraform.tfvars.example - Safe example values
│       └── prompts/
│           └── fleet-assistant-v1.txt - Initial versioned prompt text
├── golden-dataset/
│   └── dataset.jsonl               - Seed golden dataset (100 records)
├── lambda_src/
│   ├── lambda_bedrock_wrapper.py   - Bedrock wrapper with full instrumentation
│   ├── lambda_drift_detector.py    - Drift detection with SSM counter and SNS alert
│   ├── feedback_capture.py         - Dispatcher feedback capture Lambda
│   └── feedback_reingest.py        - Approved correction reingestion Lambda
├── modules/
│   ├── lambda-bedrock-wrapper/     - Wrapper Lambda, IAM, CloudWatch log group
│   ├── prompt-store/               - SSM versioned prompt and active pointer
│   ├── drift-detector/             - Drift Lambda, scheduler, SNS, log group
│   ├── eval-framework/             - S3 bucket, versioning, lifecycle, encryption
│   └── feedback-loop/              - DynamoDB, two Lambda functions, IAM roles
└── scripts/
    ├── eval_runner.py              - Offline evaluation runner
    ├── seed_metrics.py             - Seeds CloudWatch via live Lambda invocations
    ├── seed_historical_metrics.py  - Seeds 5 days of synthetic metric history
    ├── seed_drift_day.py           - Adds one stable day to position drift for testing
    └── test_drift_logic.py         - Pure Python unit test for drift statistics
```

---

## Prerequisites

### Tools

| Tool | Version | Purpose |
|---|---|---|
| Terraform | >= 1.6.0 | Infrastructure provisioning |
| AWS CLI | >= 2.13 | Authentication and CLI operations |
| Python | >= 3.12 | Lambda runtime and evaluation scripts |
| Git | Any | Version control |

### AWS Prerequisites

- IAM Identity Center configured with an SSO profile and sufficient permissions in the target account
- Terraform remote state S3 bucket and DynamoDB lock table provisioned in the management account (see Project 1)
- Amazon Bedrock model access enabled for `anthropic.claude-sonnet-4-5-20250929-v1:0` in `eu-central-1`
- Amazon Bedrock model access enabled for `amazon.titan-embed-text-v1` in `eu-central-1` (used by `eval_runner.py` for embedding scoring)

### AWS Parameters and Secrets Lambda Extension

The Bedrock wrapper Lambda uses the **AWS Parameters and Secrets Lambda Extension** to cache SSM parameters in-process. This avoids an SSM API call on every invocation at 500 invocations/minute peak load.

The extension is published by AWS as a public Lambda layer. It is not deployed by this project. The ARN is region-specific and must be retrieved before deploying.

Retrieve the ARN for `eu-central-1`:

```bash
aws lambda list-layers \
  --compatible-runtime python3.12 \
  --region eu-central-1 \
  --query "Layers[?contains(LayerName, 'AWS-Parameters-and-Secrets-Lambda-Extension')]"
```

Alternatively, the current ARN for `eu-central-1` is documented in the AWS Parameter Store integration guide:
[https://docs.aws.amazon.com/systems-manager/latest/userguide/ps-integration-lambda-extensions.html](https://docs.aws.amazon.com/systems-manager/latest/userguide/ps-integration-lambda-extensions.html)

Set the retrieved ARN as `extension_layer_arn` in `terraform.tfvars` before running `terraform apply`.

---

## Usage

### 1. Authenticate

```bash
aws sso login --profile <your-sso-profile>
aws sts get-caller-identity
```

### 2. Configure variables

```bash
cd environments/dev
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set:

```hcl
aws_region          = "eu-central-1"
environment         = "dev"
aws_account_id      = "<your-account-id>"
extension_layer_arn = "<arn-from-prerequisite-step-above>"
simulation_mode     = false
```

Set `simulation_mode = true` to deploy and test without making Bedrock API calls. All metrics and logs are still emitted with a synthetic response. This is useful for validating infrastructure without incurring token cost.

### 3. Initialise Terraform

```bash
terraform init
```

### 4. Plan and apply

```bash
terraform plan
terraform apply
```

### 5. Upload the golden dataset to S3

```bash
aws s3 cp ../../golden-dataset/dataset.jsonl \
  s3://trackhaul-llmops-dev-eval/golden-dataset/v1/dataset.jsonl
```

### 6. Seed baseline metrics

Run this to generate initial `ResponseLengthMean` data points in CloudWatch by invoking the wrapper with realistic queries:

```bash
cd ../..
python scripts/seed_metrics.py
```

Allow 2–3 minutes for metrics to appear in CloudWatch before proceeding.

### 7. Test drift detection locally

```bash
python scripts/test_drift_logic.py
```

This runs the drift statistical logic against synthetic data with no AWS calls. Confirm that `fault_lookup` and `fuel_anomaly` show as `DRIFTED` and `safety_score` shows as `stable`.

### 8. Seed synthetic metric history and trigger drift detector

To test the full drift detection pipeline in AWS:

```bash
# Seed 5 days of history with one drifted day
python scripts/seed_historical_metrics.py

# Wait 2 minutes for CloudWatch to index the metrics, then invoke the drift detector
aws lambda invoke \
  --function-name trackhaul-llmops-dev-drift-detector \
  --payload '{"source": "manual-test"}' \
  --cli-binary-format raw-in-base64-out \
  response.json

cat response.json
```

### 9. Run offline evaluation

```bash
python scripts/eval_runner.py
```

Results are printed to the console and written to `s3://trackhaul-llmops-dev-eval/eval-results/`.

---

## Prompt Governance

Prompts are stored in SSM Parameter Store under a versioned path structure:

```
/trackhaul/llmops/prompts/fleet-assistant/v1      # versioned copy — immutable
/trackhaul/llmops/prompts/fleet-assistant/active  # active pointer — Lambda reads this
```

The Lambda wrapper reads the `active` pointer at each invocation via the SSM extension cache (TTL 60 seconds). To roll back a prompt version, update the `active` SSM parameter to point to the previous version. No Lambda redeployment is required. The rollback takes effect within one cache TTL window.

To deploy a new prompt version:

1. Add a new `module "fleet_assistant_prompt_v2"` block in `environments/dev/main.tf` referencing the new prompt file
2. Run `terraform apply` — this writes the new versioned SSM parameter
3. Update the `active` pointer in SSM manually or via a canary traffic split parameter
4. Monitor Tier 1 and Tier 3 metrics for 24 hours before promoting to 100% traffic

---

## Security Considerations

**KMS customer managed key**
A single CMK covers SSM SecureString parameters, CloudWatch log groups, DynamoDB, and the eval S3 bucket. The key policy grants least-privilege access per service principal. Key rotation is enabled. The root account statement is required — without it the key becomes unmanageable if all other grants are removed.

**No PII in any layer**
The Lambda wrapper enforces a structured log schema that permits only `truck_id` as a vehicle-level identifier. Driver names, GPS coordinates, and route data do not appear in any log entry, metric dimension, or prompt. The `build_log_entry` function is the single enforcement point.

**Least privilege IAM**
Each Lambda function has its own scoped execution role. The drift detector SSM policy is scoped to the `/trackhaul/llmops/drift-counter/*` path only — it cannot read or write prompt parameters. The feedback reingest role is scoped to the `eval-candidate-index` GSI only — it cannot perform table scans.

**Prompt write access**
SSM prompt parameters are `SecureString` encrypted with the LLMOps KMS key. The Lambda execution role has `ssm:GetParameter` access only — it cannot write or overwrite prompt parameters.

**CloudWatch log retention**
All log groups have explicit retention set in Terraform. Default retention (never expires) is not used anywhere. Log groups without explicit retention accumulate cost indefinitely and can destroy compliance evidence if set too short retroactively.

**Eval S3 bucket**
Public access is blocked on all four settings. Versioning is enabled — every dataset upload is preserved, not overwritten. This protects the golden dataset from accidental overwrites during reingestion.

---

## Lessons Learned

**The SSM extension requires the session token header — without it every fetch returns 403**
The Parameters and Secrets Lambda Extension serves SSM values via a localhost HTTP endpoint on port 2773. The request must include the `X-Aws-Parameters-Secrets-Token` header set to the value of `AWS_SESSION_TOKEN` from the Lambda execution environment. This header is not documented prominently. Omitting it produces a 403 with no clear error message indicating the header is missing.

**Lambda layers use `layers = [var.extension_layer_arn]` as a list — a string value fails silently**
The `layers` attribute on `aws_lambda_function` expects a list type. Passing a string (even a valid ARN string) does not raise a Terraform error but the layer is not attached. The function deploys without the extension and the SSM fetch fails at runtime with a connection refused error on localhost:2773.

**CloudWatch `GetMetricStatistics` requires exact dimension matching — partial dimensions return empty results**
The drift detector fetches `ResponseLengthMean` using `GetMetricStatistics` with dimensions `prompt_version` and `query_type`. If the wrapper emits the metric with an additional dimension that the drift detector does not include in its query, the statistics call returns zero datapoints. Dimension sets must match exactly between the emitting code and the querying code.

**SSM consecutive drift counter must be reset on a stable day — not only incremented on a drifted day**
If the counter is only incremented on drift and never reset, a stable day after two drifted days still holds a count of 2. The next drifted day then triggers an alert as if three consecutive days had drifted, which is incorrect. The counter must be explicitly set to 0 on any stable day.

**DynamoDB GSI on `eval_candidate` requires the attribute to exist on every item — missing it silently excludes records from the index**
The `feedback_reingest` Lambda queries the `eval-candidate-index` GSI to find approved corrections. Records written by `feedback_capture` that do not include the `eval_candidate` attribute are not indexed and are never returned by the reingestion query. The capture Lambda must write `eval_candidate` on every record, even if the initial value is `"pending"`.

**Eval results bucket lifecycle — `filter` block is required even for a prefix-only rule in AWS provider >= 4.x**
The S3 lifecycle configuration for the eval results bucket requires an explicit `filter` block containing the prefix. An empty `filter {}` or omitting the block entirely causes a Terraform apply error in AWS provider version 5.x. The prefix must be declared inside the filter block, not as a top-level rule attribute.

**`simulation_mode = true` should be the default for initial infrastructure validation**
Deploying with `simulation_mode = false` on the first apply before Bedrock model access is confirmed causes every Lambda invocation to fail with an `AccessDeniedException`. Setting `simulation_mode = true` for the initial deploy validates all infrastructure — IAM roles, SSM paths, CloudWatch log groups, metric emission — without requiring Bedrock access to be active.
