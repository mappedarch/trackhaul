# TrackHaul AI Fleet Intelligence Layer — Architecture Design

> Note: TrackHaul is a fictional logistics company used as a realistic design
> target for this portfolio. All scale figures (10,000 trucks, 5,000 events/sec)
> are illustrative assumptions chosen to reflect enterprise-scale design
> constraints. All performance figures in this document are design targets,
> not measured values.

---

## 1. Business Context

TrackHaul is a fictional European logistics company operating at a scale of
10,000 trucks across Germany, Poland and the Netherlands, generating an assumed
peak of approximately 5,000 telemetry events per second. Fleet dispatchers and
operations managers cannot query fleet data without technical support. Fault
codes, fuel anomalies and driver behaviour patterns are buried in raw telemetry.
This document defines the AI architecture that addresses these operational gaps.

Three AI use cases are in scope:

- **Fleet Intelligence Assistant** — natural language querying over fleet documents and live event data
- **Autonomous Incident Response** — AI agent that diagnoses critical events and recommends or executes action
- **Intelligent Anomaly Explanation** — AI explanation layer over Kinesis-detected telemetry anomalies

---

## 2. Architecture Decision — RAG over Fine-Tuning

A retrieval-augmented generation (RAG) approach was selected over fine-tuning
for the following reasons:

- No labelled Q&A training data exists at this stage of the project
- Fleet knowledge changes frequently — new vehicles, updated fault codes, revised compliance rules
- GDPR requires auditability of what data influenced a given answer;
  fine-tuned weights do not provide this
- RAG knowledge bases can be updated independently of the model with no retraining cost

Fine-tuning introduces model drift over time and makes data residency compliance
harder to enforce at the retrieval layer. RAG keeps retrieval and generation
cleanly separated and auditable.

---

## 3. AI Use Cases and Components

### 3.1 Fleet Intelligence Assistant

**Function:** Dispatchers query fleet data in natural language.

Example queries (illustrative):
- "Which trucks had fuel anomalies in Poland this week?"
- "What does fault code P0300 mean for truck TH-4821?"
- "Show me drivers with declining safety scores this month"

**Components:**
- Bedrock Knowledge Base — indexes maintenance manuals, compliance documents, fleet event data
- OpenSearch Serverless — vector store managed by Bedrock
- Claude Sonnet (current generation, EU Geo inference profile) — foundation model for response generation
- Bedrock Guardrails — PII filtering, topic restrictions, GDPR enforcement
- ElastiCache for Redis — semantic cache layer to reduce token spend at scale (custom-built in Lambda)

### 3.2 Autonomous Incident Response

**Function:** On a critical event (engine fault, geofence breach, harsh braking
pattern), an AI agent diagnoses the issue, checks maintenance history,
recommends action, and escalates or auto-resolves.

**Components:**
- Bedrock Agents — orchestrates tool use and multi-step reasoning
- Tool definitions — fleet query, maintenance history lookup, alert dispatch, ticket creation
- Step Functions integration — hands off to existing Project 3 incident orchestration workflow
- DynamoDB — agent session state and action audit trail

### 3.3 Intelligent Anomaly Explanation

**Function:** When the Project 4 streaming layer detects a telemetry anomaly,
AI generates a plain-language explanation of what happened, why it likely
occurred, and what similar past incidents resolved to.

**Components:**
- EventBridge trigger — fires on anomaly events from Kinesis pipeline
- Lambda — invokes Bedrock with anomaly context and retrieves similar historical incidents
- Bedrock Knowledge Base — historical incident corpus
- S3 — explanation output stored for audit

---

## 4. Data Architecture and GDPR Controls

### 4.1 PII Boundary

No personally identifiable information enters any LLM invocation under any
circumstances.

| Data | Allowed in LLM context | Notes |
|---|---|---|
| Truck ID (e.g. TH-4821) | Yes | Internal reference only |
| Driver name | No | Stripped at ingestion |
| GPS coordinates | No | Stripped at ingestion |
| Driver hours raw data | No | Aggregated summaries only |
| Fault codes | Yes | Technical, non-personal |
| Fuel consumption | Yes | Aggregated at truck level |

PII stripping is enforced at two layers:
1. Lambda pre-processing before any Bedrock invocation
2. Bedrock Guardrails as a secondary defence

### 4.2 Data Residency

All Bedrock inference uses the EU Geographic cross-region inference profile.
This keeps all prompts and outputs within AWS EU regions and does not route
outside EU boundaries. This satisfies GDPR data residency requirements while
providing better throughput than a single-region In-Region configuration.

Knowledge base storage (S3, OpenSearch Serverless) is in eu-west-1.
Data residency is enforced at SCP level (Project 1) and cannot be overridden
by any workload account.

### 4.3 Knowledge Base Sources

| Source | Content | Update Frequency |
|---|---|---|
| S3 — maintenance-manuals/ | OEM fault code manuals, repair procedures | Assumed monthly |
| S3 — compliance-docs/ | GDPR policy, EU driver hours regulation | Assumed quarterly |
| S3 — fleet-events/ | Processed (PII-stripped) event summaries | Assumed daily |
| S3 — incident-history/ | Resolved incident records | Continuous |

---

## 5. Cost Architecture

At the assumed scale of 10,000 vehicles, uncontrolled token consumption is a
significant cost risk. The following controls are applied as design targets.

### 5.1 Caching Strategy

- **Semantic cache (Redis):** Common dispatcher queries (fault code lookups,
  weekly summaries) are cached by embedding similarity in Lambda before Bedrock
  is invoked. Bedrock does not provide a native semantic cache.
- TTL: design target of 1 hour for live event queries, 24 hours for
  document-based queries. Values to be tuned based on observed query patterns.

### 5.2 Tiered Response Strategy

| Query Type | Strategy | Latency Target | Cost Profile |
|---|---|---|---|
| Cache hit | Return cached response | <100ms | Near zero |
| Simple lookup | Knowledge base retrieval, no generation | <1s | Low |
| Complex query | Full RAG + generation | 2-5s | Standard |
| Agent task | Multi-step agent invocation | 5-20s | High |

All latency figures are design targets based on typical Bedrock behaviour.
Actual values depend on model load, chunk count, and prompt size.

### 5.3 Token Governance

- Token consumption tracked per truck ID and per fleet segment via CloudWatch custom metrics
- Budget alerts at 80% and 100% of monthly token budget (Project 6 — LLMOps)
- Agent invocations rate-limited per vehicle to prevent runaway costs from bad event patterns

---

## 6. Multi-Region and Failover

Primary inference: EU Geo cross-region inference profile (eu-west-1 as source region)
Knowledge base storage: eu-west-1
DR knowledge base replica: eu-central-1 via S3 Cross-Region Replication

**Failover strategy:**

Bedrock does not expose a health check endpoint suitable for Route 53 probing.
Failover is instead implemented as follows:

1. CloudWatch alarm monitors Bedrock API error rate and p99 latency from the
   primary region
2. Alarm triggers a Lambda function
3. Lambda updates an SSM Parameter Store parameter (`/trackhaul/ai/active-region`)
4. All AI Lambda functions read the active region from SSM on each invocation
5. Knowledge base sync job targets the replica bucket in eu-central-1

**Design targets:**
- RTO: under 10 minutes (CloudWatch alarm + SSM propagation)
- RPO: dependent on S3 replication lag for knowledge base; target under 1 hour

**Model fallback:**
- Primary: Claude Sonnet (current generation, EU Geo inference profile)
- Fallback: Claude Haiku (current generation) — lower capability, lower cost,
  lower latency — triggered on sustained throttling or latency breach

---

## 7. Security Architecture

### 7.1 IAM

- Bedrock Knowledge Base has its own execution role — S3 read and OpenSearch write only
- Lambda invocation roles scoped per use case — no shared roles across AI functions
- No human IAM users with Bedrock access — all access via IAM Identity Center

### 7.2 Encryption

- S3 knowledge base buckets: KMS customer managed key (ai-data classification)
- OpenSearch Serverless: encryption at rest enabled
- ElastiCache Redis: encryption at rest and in transit enabled
- All Bedrock API calls: TLS in transit; AWS does not persist prompts or outputs
  outside the invocation by default (confirm with AWS data handling addendum for
  regulated workloads)

### 7.3 Network

- Lambda functions in VPC private subnets
- Bedrock accessed via VPC endpoint (AWS PrivateLink — supported)
- OpenSearch Serverless accessed via VPC endpoint (supported)
- ElastiCache Redis in private subnet, no public endpoint
- No public endpoints on any AI layer component

### 7.4 Audit Trail

- Every Bedrock invocation logged to CloudTrail
- Input prompts and retrieved chunks logged to S3 (PII-stripped, audit bucket)
- Guardrail intervention events logged separately for compliance review

---

## 8. Build Sequence (Steps 1-9)

| Step | Build Output |
|---|---|
| 1  | Bedrock Knowledge Base — Terraform, S3 source buckets |
| 2  | RAG ingestion pipeline — chunking strategy, sync job |
| 3  | RAG retrieval layer — caching, latency optimisation |
| 4  | Prompt architecture — system prompts, few-shot examples |
| 5  | Live event data integration — EventBridge to Bedrock |
| 6  | Guardrails layer — PII filter, topic restrictions |
| 7  | Cost architecture — Redis cache, token tracking |
| 8  | Multi-region failover — SSM parameter, S3 replication |
| 9  | Security review — IAM, KMS, VPC endpoints |

