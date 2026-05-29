# TrackHaul AI Fleet Intelligence Layer

![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.6.0-623CE4?logo=terraform)
![AWS Provider](https://img.shields.io/badge/AWS%20Provider-~%3E5.49-FF9900?logo=amazon-aws)
![Pinecone Provider](https://img.shields.io/badge/Pinecone%20Provider-~%3E0.7-blue)
![License](https://img.shields.io/badge/License-MIT-green)

A GDPR-compliant AI fleet intelligence layer built on AWS Bedrock. Dispatcher queries in natural language are answered by a hybrid RAG pipeline that retrieves from both a Bedrock Knowledge Base over fleet documents and live vehicle event data from DynamoDB. All inference stays within EU regions. No PII enters any LLM prompt. Guardrails enforce GDPR compliance at the Lambda boundary before any retrieval or generation occurs.

---

## Architecture

```
Dispatcher Query
      |
      v
+-----------------------------+
|  Fleet Intelligence Lambda  |
|  fleet_intelligence_handler |
+----+------------------------+
     |
     | 1. Apply guardrail on raw query (Bedrock Guardrails)
     |    - Block PII: names, addresses, driver IDs
     |    - Block denied topics: driver personal data
     |    - Block off-topic via system prompt contract
     |
     | 2. Retrieve from Bedrock Knowledge Base (static docs)
     |    - Maintenance manuals
     |    - Fault code references
     |    - Compliance documents
     |
     | 3. Retrieve live events from DynamoDB
     |    - Query by truck_id or region (never scan)
     |    - TruckRecordTypeIndex GSI and RegionIndex GSI
     |
     | 4. Build prompt and invoke Bedrock via failover chain
     |
     v
+-----------------------------+     +---------------------------+
|  Bedrock Runtime            |     |  Failover Chain           |
|  eu-central-1 (primary)     |---->|  1. eu-central-1 Sonnet   |
|  eu-west-1    (fallback)    |     |  2. eu-west-1 Sonnet      |
+-----------------------------+     |  3. eu-west-1 Haiku       |
                                    +---------------------------+
                                             |
                                    Circuit Breaker (DynamoDB)
                                    Trips after 3 failures/region
                                    Auto-resets after 60s via TTL

Supporting infrastructure:
- Pinecone vector index (embedding store for KB)
- DynamoDB RAG cache (TTL-based, keyed on query hash)
- DynamoDB token tracker (per-vehicle cost attribution)
- KMS CMKs — separate keys per data classification boundary
```

**Primary region:** eu-central-1  
**DR / failover region:** eu-west-1  
**Embedding model:** Amazon Titan Embed Text V2 (1024 dimensions)  
**Generation models:** Claude Sonnet (primary), Claude Haiku (degraded fallback)  
**Vector store:** Pinecone serverless index  
**No PII in any LLM prompt — truck IDs only**

---

## Query Flow

| Step | Component | Notes |
|---|---|---|
| 1 | Bedrock Guardrails `apply_guardrail` | Applied to raw user query before any retrieval |
| 2 | Bedrock Knowledge Base `retrieve` | Top-5 chunks from fleet documents |
| 3 | DynamoDB GSI query | Live vehicle events by truck_id or region |
| 4 | Model router | Routes simple queries to Haiku, complex to Sonnet |
| 5 | Bedrock `invoke_model` | EU cross-region inference profile |
| 6 | Circuit breaker | DynamoDB-backed, shared across all Lambda instances |
| 7 | RAG cache write | SHA256 query hash key, TTL by query type |

### Cache TTL Strategy

| Query Type | TTL | Rationale |
|---|---|---|
| Static doc queries (fault codes, manuals) | 24 hours | Content changes infrequently |
| Maintenance history queries | 1 hour | Semi-live data |
| Live event queries (anomalies, incidents) | No cache | Always fetched fresh |

---

## Guardrail Configuration

The Bedrock guardrail (`trackhaul-{env}-fleet-guardrail`) enforces GDPR compliance on every query before KB retrieval or model invocation.

| Control | Type | Action |
|---|---|---|
| Driver names | PII — NAME | ANONYMIZE on input |
| Email addresses | PII — EMAIL | ANONYMIZE on input |
| Phone numbers | PII — PHONE | ANONYMIZE on input |
| Driver IDs | PII — DRIVER_ID | BLOCK |
| Vehicle identification numbers | PII — VIN | BLOCK |
| Driver personal data queries | Denied topic | BLOCK |
| Hate, insults, violence | Content filter | MEDIUM threshold |
| Sexual content | Content filter | HIGH threshold |
| Off-topic queries | System prompt rule 6 | Blocked at generation layer |

---

## Module Reference

| Module | Path | Description |
|---|---|---|
| `ai-security` | `modules/ai-security` | Three KMS CMKs (S3, DynamoDB, CloudWatch). IAM roles and scoped inline policies for fleet intelligence Lambda and token tracker Lambda. Key policies per service principal. |
| `s3-kb-source` | `modules/s3-kb-source` | S3 bucket for Knowledge Base source documents. CMK encrypted. TLS-only bucket policy. Public access blocked. |
| `pinecone` | `modules/pinecone` | Pinecone serverless index. 1024-dimension cosine metric. Matches Titan Embed Text V2 output. |
| `bedrock-kb` | `modules/bedrock-kb` | Bedrock Knowledge Base created via `null_resource` local-exec. Titan Embed Text V2 embedding model. Pinecone as vector store. IAM role for KB with S3 read and Secrets Manager access for Pinecone API key. |
| `bedrock-guardrails` | `modules/bedrock-guardrails` | GDPR guardrail with PII detection, denied topics, and content filters. Published version used by Lambda. |
| `dynamodb-cache` | `modules/dynamodb-cache` | RAG query cache. PAY_PER_REQUEST. SHA256 query hash as partition key. TTL on `expires_at`. CMK encrypted. |
| `token-tracker` | `modules/token-tracker` | Token consumption tracker per vehicle and per fleet. PAY_PER_REQUEST. Composite key (pk, sk). PITR enabled. CMK encrypted. |
| `bedrock-failover` | `modules/bedrock-failover` | Circuit breaker state table. Region as partition key. TTL on `reset_at` for automatic reset after 60 seconds. |
| `lambda-fleet-intelligence` | `modules/lambda-fleet-intelligence` | Fleet Intelligence Lambda. Python 3.12. 256 MB, 30s timeout. Hybrid RAG handler with guardrail check, KB retrieval, DynamoDB live event query, model routing, and failover invocation. |

---

## Repository Structure

```
trackhaul-ai-layer/
├── docs/
│   └── ai-architecture.md          - Full AI architecture design document
├── environments/
│   └── dev/
│       ├── main.tf                 - Module orchestration for dev environment
│       ├── variables.tf            - Variable declarations
│       ├── outputs.tf              - Environment outputs
│       ├── backend.tf              - Remote state configuration
│       └── terraform.tfvars        - Variable values (not committed)
├── lambda_src/
│   ├── fleet_intelligence_handler.py  - Hybrid RAG Lambda handler
│   ├── bedrock_client.py              - Failover chain and circuit breaker
│   ├── model_router.py                - Query classification and model routing
│   └── token_tracker.py               - Token consumption tracking
├── modules/
│   ├── ai-security/                - KMS keys and IAM roles
│   ├── bedrock-failover/           - Circuit breaker DynamoDB table
│   ├── bedrock-guardrails/         - GDPR guardrail
│   ├── bedrock-kb/                 - Bedrock Knowledge Base
│   ├── dynamodb-cache/             - RAG query cache
│   ├── lambda-fleet-intelligence/  - Fleet Intelligence Lambda
│   ├── pinecone/                   - Pinecone vector index
│   ├── s3-kb-source/               - Knowledge Base source S3 bucket
│   ├── secrets/                    - Secrets Manager resources
│   └── token-tracker/              - Token tracking DynamoDB table
├── prompts/
│   └── v1/
│       ├── fleet_query.json        - Fleet dispatcher query contract
│       ├── fault_diagnosis.json    - Fault code diagnosis contract
│       ├── anomaly_explanation.json- Anomaly explanation contract
│       └── incident_summary.json   - Incident summary contract
├── sample-docs/
│   ├── maintenance-manual-engine.txt  - Engine fault codes (P0300, P0171)
│   ├── fuel-anomaly-reference.txt     - Fuel anomaly thresholds and types
│   └── compliance-driver-hours.txt    - EU driver hours compliance reference
└── scripts/
    ├── retrieve.py                 - Standalone RAG retrieval test script
    ├── test_guardrails.py          - Guardrail validation script
    ├── prompt_manager.py           - Prompt contract loader
    ├── seed_fleet_data.py          - DynamoDB test data seeder
    └── debug_query.py              - Query debugging utility
```

---

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Terraform | >= 1.6.0 | Infrastructure provisioning |
| AWS CLI | >= 2.13 | Authentication and CLI operations |
| Python | >= 3.12 | Lambda runtime and test scripts |
| Git | Any | Version control |

AWS prerequisites:
- IAM Identity Center configured with an SSO profile and sufficient permissions in the target account
- Terraform remote state S3 bucket provisioned in the management account (`trackhaul-terraform-state-{account_id}`)
- Terraform remote state DynamoDB lock table provisioned in the management account (`trackhaul-terraform-locks`)
- Pinecone account with an API key stored in Secrets Manager at `trackhaul/dev/pinecone-api-key`
- KMS key from `trackhaul-fleet-api` project accessible via alias `alias/trackhaul-dynamodb-dev` (used to decrypt the vehicles table)

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
project          = "trackhaul"
environment      = "dev"
aws_region       = "eu-central-1"
account_id       = "<your-account-id>"
pinecone_api_key = "<your-pinecone-api-key>"
EOF
```

### 3. Initialise Terraform

```bash
terraform init
```

### 4. Apply

```bash
# Security and KMS first — other modules depend on its outputs
terraform apply -target=module.ai_security -auto-approve

# Then remaining modules
terraform apply -auto-approve
```

### 5. Seed Knowledge Base documents

```bash
aws s3 cp ../../sample-docs/ s3://$(terraform output -raw s3_bucket_name)/ --recursive
```

### 6. Trigger Knowledge Base sync

```bash
# Get data source ID
aws bedrock-agent list-data-sources \
  --knowledge-base-id <kb-id> \
  --region eu-central-1

# Start ingestion
aws bedrock-agent start-ingestion-job \
  --knowledge-base-id <kb-id> \
  --data-source-id <data-source-id> \
  --region eu-central-1
```

### 7. Test RAG retrieval locally

```bash
cd scripts
python retrieve.py --query "What is fault code P0300 and what action is required?" --contract fleet-query
```

### 8. Test guardrails

```bash
python test_guardrails.py
```

### 9. Invoke the Fleet Intelligence Lambda

```bash
aws lambda invoke \
  --function-name trackhaul-dev-fleet-intelligence \
  --region eu-central-1 \
  --payload '{"query": "What is fault code P0300 and what action is required?", "filters": {}}' \
  --cli-binary-format raw-in-base64-out \
  response.json && cat response.json
```

### 10. Invoke with filters

```bash
# Filter by region
aws lambda invoke \
  --function-name trackhaul-dev-fleet-intelligence \
  --region eu-central-1 \
  --payload '{"query": "Which trucks have fuel anomalies?", "filters": {"region": "PL"}}' \
  --cli-binary-format raw-in-base64-out \
  response.json && cat response.json

# Filter by truck ID
aws lambda invoke \
  --function-name trackhaul-dev-fleet-intelligence \
  --region eu-central-1 \
  --payload '{"query": "What is the status of this truck?", "filters": {"truck_id": "TH-1023"}}' \
  --cli-binary-format raw-in-base64-out \
  response.json && cat response.json
```

---

## Security Considerations

**No PII in LLM prompts**
Guardrails apply `apply_guardrail` on the raw user query before KB retrieval or model invocation. Queries containing driver names, addresses, phone numbers, or driver IDs are blocked at the Lambda boundary. The system prompt contract independently enforces truck-ID-only responses at the generation layer.

**EU data residency**
All Bedrock inference uses EU cross-region inference profiles scoped to `eu-central-1` and `eu-west-1`. The IAM policy on the Lambda role restricts `bedrock:InvokeModel` to EU inference profile ARNs and EU foundation model ARNs only. No inference routes outside EU regions.

**KMS customer managed keys**
Three separate CMKs cover distinct data classification boundaries: S3 KB source bucket, DynamoDB tables (cache, token tracker), and CloudWatch Logs. Key rotation is enabled on all three. Key policies follow least-privilege per service principal — no wildcard principals.

**Cross-project KMS dependency**
The `trackhaul-vehicles-dev` DynamoDB table is owned by the `trackhaul-fleet-api` project and encrypted with its KMS key (`alias/trackhaul-dynamodb-dev`). The fleet intelligence Lambda role is granted `kms:Decrypt` and `kms:GenerateDataKey` on that key via its IAM policy. The key is referenced via alias data source — no ARN hardcoding.

**Least privilege IAM**
The fleet intelligence Lambda role has separate inline policies per permission boundary: Bedrock invoke and retrieve, DynamoDB query on specific table ARNs including GSI paths, KMS decrypt on specific key ARNs, and Bedrock guardrail application. No managed policies beyond `AWSLambdaBasicExecutionRole`.

**Circuit breaker — shared state across instances**
The circuit breaker state is stored in DynamoDB, not Lambda memory. All concurrent Lambda instances share the same circuit breaker state. A tripped region is skipped by all instances immediately. The `reset_at` TTL resets the state automatically after 60 seconds without manual intervention.

**Guardrail version management**
A published guardrail version is created alongside the DRAFT. The Lambda references DRAFT during development. Before production promotion, a new version must be published and the Lambda environment variable updated. Publishing a version is irreversible — DRAFT changes do not affect published versions.

---

## Lessons Learned

**Bedrock Knowledge Base — `null_resource` required in eu-central-1**
At the time of implementation, the `aws_bedrockagent_knowledge_base` Terraform resource was not stable in `eu-central-1`. The Knowledge Base is created via a `null_resource` local-exec wrapping the AWS CLI `create-knowledge-base` command. This creates state management complexity — the resource is not tracked in Terraform state beyond the null resource trigger hash. Destroying and recreating requires manual deletion of the Knowledge Base via CLI before re-applying.

**KMS alias clash across projects**
The `ai-security` module originally used the alias name `alias/trackhaul-dynamodb-dev`, which collided with the same alias created by the `trackhaul-fleet-api` project. The alias was overwritten, causing the vehicles table to become inaccessible. The fix was to rename the ai-security alias to `alias/trackhaul-ai-dynamodb-dev` and restore the fleet-api alias by re-applying that project. When naming KMS aliases across a multi-project account, always include the project or service name in the alias to prevent collisions.

**Guardrail version vs DRAFT — behaviour diverges silently**
The published guardrail version (version 1) and DRAFT can behave differently if the guardrail was modified after publishing. In this project, a topic policy added to DRAFT was not reflected in version 1, causing the Lambda (which used version 1 via the `guardrail_version` output) to over-block legitimate fleet queries. Always test against the same version the Lambda will use. Publish a new version after every guardrail change.

**`apply_guardrail` must target the raw user query — not the full prompt**
Applying the guardrail inside `invoke_model` on the full assembled prompt (KB context + system prompt + user query) produces false negatives. The guardrail topic policy matches on short, direct phrases. When the user query is embedded inside thousands of tokens of context, the topic classifier fails to match. The guardrail must be applied to the raw user query string only, before KB retrieval.

**EU inference profiles route internally to unexpected regions**
EU cross-region inference profiles (`eu.anthropic.claude-*`) route internally across `eu-central-1`, `eu-west-1`, and `eu-north-1`. The IAM policy must allow `bedrock:InvokeModel` on foundation model ARNs with a wildcard region (`arn:aws:bedrock:*::foundation-model/...`) in addition to the inference profile ARNs. Restricting to `eu-central-1` and `eu-west-1` only causes `AccessDeniedException` when the profile internally routes to `eu-north-1`.

**Model router must return region alongside model ID**
The model router classifies queries and returns a model ID. When the preferred model ID is passed to the failover chain, the chain uses the primary region (`eu-central-1`) regardless of which model was selected. Claude Haiku is only available via the EU inference profile in `eu-west-1`. Passing only the model ID without the corresponding region causes the primary invocation to fail immediately and exhaust the failover chain. The router must return both `model_id` and `region` together.

**Lambda zip packaging — source files duplicated if package folder contains copies**
When `pip install -t lambda_src/package/` is run and source files are also copied into the package folder, the zip packaging loop adds them twice — once explicitly from `lambda_src/` and once from the package folder walk. Duplicate entries in a Lambda zip cause the runtime to load whichever copy appears last, which may be stale. Always skip root-level `.py` files during the package folder walk when they are being added explicitly.
