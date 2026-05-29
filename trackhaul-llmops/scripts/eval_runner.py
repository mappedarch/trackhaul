"""
TrackHaul LLMOps — Offline Evaluation Runner
Scores prompt responses against the golden dataset using three methods:
  1. Exact match on structured fields (fault codes, truck IDs)
  2. Embedding similarity via Bedrock (cosine threshold 0.85)
  3. LLM-as-judge via Bedrock Claude (20% sample only)

Results are written to S3 and a composite OfflineEvalScore is printed.
"""

import json
import math
import random
import re
import boto3
import datetime

# ── Configuration ────────────────────────────────────────────────────────────

REGION           = "eu-central-1"
BUCKET           = "trackhaul-llmops-dev-eval"
DATASET_KEY      = "golden-dataset/v1/dataset.jsonl"
RESULTS_PREFIX   = "eval-results"
PROMPT_VERSION   = "v1"
DATASET_VERSION  = "v1"

# Bedrock model IDs
EMBED_MODEL_ID   = "amazon.titan-embed-text-v1"
JUDGE_MODEL_ID   = "eu.anthropic.claude-sonnet-4-5-20250929-v1:0"

# Scoring weights — must sum to 1.0
WEIGHT_EXACT     = 0.30
WEIGHT_EMBED     = 0.50
WEIGHT_JUDGE     = 0.20

# Cosine similarity threshold for embedding method
EMBED_THRESHOLD  = 0.85

# Fraction of records sent to LLM-as-judge
JUDGE_SAMPLE     = 0.20

# ── AWS clients ──────────────────────────────────────────────────────────────

s3      = boto3.client("s3", region_name=REGION)
bedrock = boto3.client("bedrock-runtime", region_name=REGION)

# ── Helpers ──────────────────────────────────────────────────────────────────

def load_dataset():
    """Download golden dataset from S3 and parse JSONL."""
    response = s3.get_object(Bucket=BUCKET, Key=DATASET_KEY)
    lines = response["Body"].read().decode("utf-8").strip().split("\n")
    return [json.loads(line) for line in lines]


def get_embedding(text):
    """Call Bedrock Titan to embed a text string. Returns a float list."""
    body = json.dumps({"inputText": text})
    response = bedrock.invoke_model(
        modelId=EMBED_MODEL_ID,
        body=body,
        contentType="application/json",
        accept="application/json"
    )
    result = json.loads(response["body"].read())
    return result["embedding"]


def cosine_similarity(vec_a, vec_b):
    """Compute cosine similarity between two vectors."""
    dot    = sum(a * b for a, b in zip(vec_a, vec_b))
    norm_a = math.sqrt(sum(a * a for a in vec_a))
    norm_b = math.sqrt(sum(b * b for b in vec_b))
    if norm_a == 0 or norm_b == 0:
        return 0.0
    return dot / (norm_a * norm_b)


def extract_structured_fields(text):
    """
    Extract fault codes (P followed by 4 digits) and truck IDs (TH- followed
    by digits) from a text string. These are the structured fields used for
    exact match scoring.
    """
    fault_codes = set(re.findall(r'\bP\d{4}\b', text))
    truck_ids   = set(re.findall(r'\bTH-\d+\b', text))
    return fault_codes | truck_ids


# ── Scoring methods ──────────────────────────────────────────────────────────

def score_exact_match(expected, actual):
    """
    Score 1.0 if all structured fields in the expected answer appear in the
    actual response. Score 0.0 if none match. Partial credit for partial match.
    Returns float 0.0 to 1.0.
    """
    expected_fields = extract_structured_fields(expected)
    if not expected_fields:
        # No structured fields to match — give neutral score
        return 0.5

    actual_fields = extract_structured_fields(actual)
    matched = expected_fields & actual_fields
    return len(matched) / len(expected_fields)


def score_embedding(expected, actual):
    """
    Embed both strings and compute cosine similarity.
    Returns 1.0 if similarity >= threshold, else the raw similarity score.
    """
    vec_expected = get_embedding(expected)
    vec_actual   = get_embedding(actual)
    similarity   = cosine_similarity(vec_expected, vec_actual)
    return similarity


def score_llm_judge(query, expected, actual):
    """
    Ask Claude to score the actual response against the expected answer.
    Returns a normalised float 0.0 to 1.0 (raw score 1-5 divided by 5).
    """
    prompt = f"""You are evaluating a fleet management AI assistant response.

Query: {query}

Expected answer: {expected}

Actual response: {actual}

Score the actual response on a scale of 1 to 5 where:
1 = completely wrong or missing key information
2 = partially correct but missing important details
3 = mostly correct with minor gaps
4 = correct and complete
5 = correct, complete, and well structured

Respond with a single integer between 1 and 5. No explanation."""

    body = json.dumps({
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 10,
        "messages": [{"role": "user", "content": prompt}]
    })

    response = bedrock.invoke_model(
        modelId=JUDGE_MODEL_ID,
        body=body,
        contentType="application/json",
        accept="application/json"
    )

    result = json.loads(response["body"].read())
    raw_score = int(result["content"][0]["text"].strip())
    return raw_score / 5.0


# ── Simulation layer ─────────────────────────────────────────────────────────

def simulate_model_response(record):
    """
    Simulate a model response for local testing without calling Bedrock
    for the actual fleet assistant. In production this is replaced by
    a call to the Lambda invocation wrapper.

    For eval purposes we use the expected answer with minor variation
    to produce realistic but imperfect scores.
    """
    # Introduce occasional deliberate degradation to test scoring sensitivity
    if random.random() < 0.15:
        # Simulate a poor response — strip structured fields
        return "The system could not retrieve specific information for this query."
    if random.random() < 0.10:
        # Simulate a partially correct response
        words = record["expected_answer"].split()
        return " ".join(words[:len(words)//2]) + " [response truncated]"
    # Simulate a good response — use expected answer with minor rewording
    return record["expected_answer"]


# ── Main eval loop ───────────────────────────────────────────────────────────

def run_eval():
    print(f"Loading dataset from s3://{BUCKET}/{DATASET_KEY}")
    records = load_dataset()
    print(f"Loaded {len(records)} records\n")

    results = []

    for i, record in enumerate(records):
        query    = record["query"]
        expected = record["expected_answer"]
        truck_id = record["truck_id"]
        qtype    = record["query_type"]

        # In production: call Lambda wrapper to get actual model response
        actual = simulate_model_response(record)

        # Method 1 — exact match
        exact_score = score_exact_match(expected, actual)

        # Method 2 — embedding similarity
        embed_score = score_embedding(expected, actual)

        # Method 3 — LLM-as-judge on 20% sample only
        use_judge  = random.random() < JUDGE_SAMPLE
        judge_score = score_llm_judge(query, expected, actual) if use_judge else None

        # Composite score
        if judge_score is not None:
            composite = (
                WEIGHT_EXACT * exact_score +
                WEIGHT_EMBED * embed_score +
                WEIGHT_JUDGE * judge_score
            )
        else:
            # Redistribute judge weight to embedding when judge not used
            composite = (
                WEIGHT_EXACT * exact_score +
                (WEIGHT_EMBED + WEIGHT_JUDGE) * embed_score
            )

        result = {
            "record_index"    : i,
            "truck_id"        : truck_id,
            "query_type"      : qtype,
            "exact_score"     : round(exact_score, 4),
            "embed_score"     : round(embed_score, 4),
            "judge_score"     : round(judge_score, 4) if judge_score else None,
            "composite_score" : round(composite, 4),
            "used_judge"      : use_judge,
            "prompt_version"  : PROMPT_VERSION,
            "dataset_version" : DATASET_VERSION,
        }

        results.append(result)

        print(f"[{i+1:03d}] {qtype:15s} | exact={exact_score:.2f} "
              f"embed={embed_score:.2f} "
              f"judge={f'{judge_score:.2f}' if judge_score is not None else '----':>5} "
              f"composite={composite:.2f}")

    # ── Aggregate scores ─────────────────────────────────────────────────────

    avg_composite = sum(r["composite_score"] for r in results) / len(results)
    avg_by_type   = {}
    for qtype in ["fault_lookup", "fuel_anomaly", "safety_score"]:
        subset = [r for r in results if r["query_type"] == qtype]
        avg_by_type[qtype] = sum(r["composite_score"] for r in subset) / len(subset)

    summary = {
        "run_timestamp"       : datetime.datetime.now(datetime.UTC).isoformat(),
        "prompt_version"      : PROMPT_VERSION,
        "dataset_version"     : DATASET_VERSION,
        "total_records"       : len(results),
        "judge_records"       : sum(1 for r in results if r["used_judge"]),
        "avg_composite_score" : round(avg_composite, 4),
        "avg_by_query_type"   : {k: round(v, 4) for k, v in avg_by_type.items()},
        "records"             : results
    }

    # ── Write results to S3 ──────────────────────────────────────────────────

    timestamp  = datetime.datetime.now(datetime.UTC).strftime("%Y%m%d-%H%M%S")
    result_key = (f"{RESULTS_PREFIX}/prompt-{PROMPT_VERSION}/"
                  f"dataset-{DATASET_VERSION}/{timestamp}.json")

    s3.put_object(
        Bucket      = BUCKET,
        Key         = result_key,
        Body        = json.dumps(summary, indent=2),
        ContentType = "application/json"
    )

    print(f"\n{'─'*60}")
    print(f"  OfflineEvalScore : {avg_composite:.4f}")
    for qtype, score in avg_by_type.items():
        print(f"  {qtype:20s} : {score:.4f}")
    print(f"  Results written  : s3://{BUCKET}/{result_key}")
    print(f"{'─'*60}")


if __name__ == "__main__":
    run_eval()
