# TrackHaul LLMOps Monitoring Strategy

## 1. Scope and Context

This document defines the observability, prompt governance, drift detection,
cost governance, and operational strategy for the TrackHaul AI Fleet
Intelligence Layer running on Amazon Bedrock in eu-central-1.

The system serves dispatchers and operations managers querying a fleet of
10,000 trucks in natural language. At peak, the system processes approximately
500 LLM invocations per minute across three query types: fault code lookup,
fuel anomaly investigation, and driver safety scoring.

All strategy decisions are constrained by:
- GDPR — no PII in logs, prompts, or metrics
- EU data residency — all inference in eu-central-1 and eu-west-1 only
- Cost governance — token consumption tracked per vehicle and per fleet region

---

## 2. Instrumentation Architecture

All Bedrock invocations pass through a Lambda wrapper function.
Bedrock is never called directly from application code.

The wrapper is responsible for:
1. Injecting the active prompt version from SSM Parameter Store
2. Recording invocation start timestamp
3. Calling Bedrock InvokeModel
4. Extracting input_tokens and output_tokens from response metadata
5. Emitting custom CloudWatch metrics with structured dimensions
6. Writing a structured interaction log to CloudWatch Logs (no PII)
7. Returning the response to the caller

This single instrumentation point ensures consistent metric coverage
regardless of which upstream service triggers the query.

---

## 3. Metrics Strategy

Metrics are organised into three tiers by operational purpose.

### Tier 1 — Operational Metrics (alarm on these)

These metrics indicate system health. Breaching thresholds requires
immediate operational response.

| Metric Name | Dimensions | Alarm Threshold | Rationale |
|---|---|---|---|
| InvocationLatencyP95 | model_id, query_type | > 3000ms | Dispatcher SLA |
| InvocationLatencyP99 | model_id, query_type | > 5000ms | Tail latency — P99 can be 3–5x mean during throttling |
| InvocationErrorRate | model_id | > 2% over 5 min | Sustained errors indicate model or quota issue |
| ThrottledRequestCount | model_id | > 0 | Bedrock quota exhaustion — triggers fallback |
| InputTokensPerRequest | query_type | > 4000 | Approaching model context limit — prompt bloat signal |
| GuardrailTriggerRate | guardrail_id | > 1% over 15 min | Sustained PII or safety boundary breaches |

**Why P95 and P99 and not mean:**
Mean latency masks tail behaviour. During Bedrock throttling or model
load events, P99 latency spikes while the mean remains acceptable.
Dispatchers experience the tail, not the mean. Production systems that
alarm only on mean latency consistently miss the events users complain about.

### Tier 2 — Cost Governance Metrics (report and budget on these)

These metrics drive cost visibility and chargeback. They are published
to a dedicated CloudWatch namespace: `TrackHaul/LLMCost`.

| Metric Name | Dimensions | Purpose |
|---|---|---|
| InputTokensTotal | truck_id, model_id, fleet_region | Per-vehicle input cost attribution |
| OutputTokensTotal | truck_id, model_id, fleet_region | Per-vehicle output cost attribution |
| EstimatedCostUSD | fleet_region, model_id | Budget forecasting by region |
| CacheHitRate | query_type | Measures effectiveness of semantic cache layer |
| InvocationsTotal | query_type, fleet_region | Volume baseline for capacity planning |

**Input and output tokens are always separate dimensions.**
Bedrock prices input and output tokens differently per model. A single
TotalTokens metric is insufficient for accurate cost attribution and
becomes misleading when models are switched or compared.

**Cost ceiling and throttling response:**
A CloudWatch alarm on EstimatedCostUSD triggers an SNS notification to
the ops team at 80% of monthly budget. At 100%, a Lambda function sets
an SSM parameter flag that the invocation wrapper checks before calling
Bedrock, returning a cached or degraded response instead of a live
invocation. This prevents unbounded spend at 10,000 vehicle scale.

### Tier 3 — Quality and Drift Metrics (trend over time)

These metrics do not trigger immediate alarms. They are tracked as
weekly trends and feed the drift detection process defined in Section 5.

| Metric Name | Dimensions | Purpose |
|---|---|---|
| ResponseLengthMean | prompt_version, query_type | Verbosity drift baseline |
| ResponseLengthVariance | prompt_version, query_type | Statistical drift signal |
| FallbackModelRate | — | Primary model degradation proxy |
| UserCorrectionRate | query_type | Response quality proxy from feedback loop |
| OfflineEvalScore | prompt_version, eval_dataset_version | Automated quality score against golden dataset |

---

## 4. Baseline Definition

Drift cannot be detected without a defined baseline. The following
baselining process is applied at initial deployment and after any
prompt version change.

**Baselining period:** 14 days of production traffic after a stable
prompt version is deployed.

**Baseline metrics captured:**
- Mean and standard deviation of ResponseLengthMean per query_type
- Mean and standard deviation of InvocationLatencyP95 per model_id
- OfflineEvalScore against the initial golden dataset

**Drift threshold:** A metric is flagged as drifted when it exceeds
2 standard deviations from its 14-day rolling baseline for 3 consecutive
daily measurement windows. A single-day exceedance is treated as noise.

**Baseline reset:** The baseline resets after a deliberate prompt version
change. The new baseline period begins from the point the new version
reaches 100% traffic. Baselines are never reset manually without a
corresponding prompt version increment.

---

## 5. Prompt Governance

### Storage

Prompts are stored in AWS SSM Parameter Store using a versioned path structure:

```
/trackhaul/prompts/{prompt_name}/{version}    # versioned copy
/trackhaul/prompts/{prompt_name}/active       # points to active version
```

### Deployment Process

1. New prompt version written to SSM at the next version number
2. Canary deployment: active pointer updated to new version for 10% of
   invocations (controlled by a traffic-split parameter in SSM)
3. Tier 1 and Tier 3 metrics monitored for 24 hours on canary traffic
4. If no regression: active pointer updated to 100%
5. If regression detected: active pointer reverted to previous version —
   Lambda picks up the change on next cold start

### Why SSM and Not Hardcoded Prompts

A prompt change has the same blast radius as a code deployment affecting
all users simultaneously. SSM Parameter Store provides versioning,
audit trail via CloudTrail, IAM-controlled write access, and rollback
without a code deployment. Hardcoded prompts require a Lambda deployment
to roll back, which adds 5–10 minutes to incident response time.

---

## 6. Evaluation Framework

### Golden Dataset

A golden dataset of 100 query/answer pairs is maintained in S3 at:

```
s3://trackhaul-llmops-eval/golden-dataset/v{version}/dataset.jsonl
```

Each record contains:
- `query` — the dispatcher question
- `expected_answer` — the reference answer
- `query_type` — fault_lookup | fuel_anomaly | safety_score
- `truck_id` — a synthetic non-PII identifier

**Who creates the golden dataset:**
Initial records are authored by operations managers and fleet engineers
during a structured review session. New records are added from the
feedback loop (Section 7) when a dispatcher correction is marked as
high-confidence by a reviewer.

**Dataset versioning:**
The dataset is versioned independently of prompts. An eval run always
records both the prompt_version and eval_dataset_version as dimensions
so regressions can be attributed correctly.

### Scoring Method

Three scoring methods are applied per eval run:

| Method | What It Measures | When It Fails |
|---|---|---|
| Exact match on structured fields | Fault codes, truck IDs in response | Verbose or reworded correct answers |
| Embedding similarity (cosine > 0.85) | Semantic correctness | Factually wrong but topically similar answers |
| LLM-as-judge (Bedrock Claude) | Overall answer quality 1–5 | Adds token cost — used on 20% sample of dataset |

A composite OfflineEvalScore is calculated as a weighted average.
The score is emitted as a CloudWatch custom metric after each weekly eval run.

### Eval Run Schedule

- Weekly automated run via EventBridge Scheduler → Lambda
- On-demand run triggered by any prompt version canary deployment
- Results published to CloudWatch and written to S3 for audit

---

## 7. Alerting and Escalation

A CloudWatch alarm with no escalation path is not operational.
The following escalation matrix applies:

| Alarm | Severity | Escalation |
|---|---|---|
| InvocationErrorRate > 2% | P2 | SNS → ops-alerts Slack channel |
| ThrottledRequestCount > 0 | P2 | SNS → ops-alerts + triggers fallback model Lambda |
| InvocationLatencyP99 > 5000ms | P2 | SNS → ops-alerts Slack channel |
| GuardrailTriggerRate > 1% | P1 | SNS → security-alerts + GDPR incident log entry |
| EstimatedCostUSD at 80% budget | P3 | SNS → finance-alerts email |
| EstimatedCostUSD at 100% budget | P1 | SNS → ops-alerts + Lambda throttle enforcer activated |
| OfflineEvalScore drops > 10% week-on-week | P2 | SNS → ai-team + prompt review initiated |

**Runbooks:**
Each P1 and P2 alarm has a corresponding runbook stored in `docs/runbooks/`.
The runbook defines the diagnosis steps, rollback procedure, and escalation
contacts. Alarms without runbooks are not considered production-ready.

---

## 8. Log Management

| Log Group | Retention | Archive Target | Rationale |
|---|---|---|---|
| /trackhaul/llm/interactions | 30 days active | S3 after 30 days, 90 days total | Operational debugging window |
| /trackhaul/llm/errors | 90 days active | S3 after 90 days | Incident investigation |
| /trackhaul/llm/guardrails | 365 days active | S3 after 365 days | GDPR compliance artefact |
| /trackhaul/llm/eval | 365 days active | S3 after 365 days | Audit trail for quality decisions |

All log groups are encrypted with a KMS customer managed key scoped
to the LLMOps boundary. No driver names, GPS coordinates, or personal
identifiers appear in any log entry. Truck IDs are the only
vehicle-level identifier permitted.

**Default retention is a production trap.**
CloudWatch log groups created without explicit retention either
accumulate cost indefinitely or are set to a short window that
destroys compliance evidence. Retention must be set explicitly
in Terraform for every log group, not left to default.

---

## 9. GDPR Compliance Controls

| Control | Implementation |
|---|---|
| No PII in prompts | Guardrails layer blocks driver names and GPS before Bedrock invocation |
| No PII in logs | Structured log schema enforced in Lambda wrapper — only truck_id permitted |
| No PII in metrics | Metric dimensions use truck_id only — never driver_id or route coordinates |
| Data residency | Bedrock invocations in eu-central-1 only. Fallback to eu-west-1 only |
| Audit trail | All guardrail trigger events written to /trackhaul/llm/guardrails with 365-day retention |
| Access control | SSM prompt parameters readable by Lambda execution role only. Write access restricted to prompt-admin permission set in IAM Identity Center |
