"""
TrackHaul RAG Retrieval Script — retrieve.py
Day 25 cache-aware retrieval + Day 26 prompt manager integration.

Flow:
  1. Hash query → check DynamoDB cache
  2. Cache hit  → return cached response (no Bedrock call)
  3. Cache miss → retrieve chunks from Bedrock KB
              → build prompt payload via PromptManager
              → call Bedrock converse API with EU inference profile
  4. Write response to DynamoDB cache with TTL
  5. Print answer, sources, token usage

Constraints:
  - Inference stays in eu-central-1 via EU cross-region inference profile
  - No PII enters query or context — truck IDs only
  - All GDPR constraints enforced in system prompt via PromptManager
"""

import argparse
import hashlib
import json
import logging
import sys
import time

import boto3
from botocore.exceptions import ClientError

from prompt_manager import PromptManager

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

REGION            = "eu-central-1"
KNOWLEDGE_BASE_ID = "G8TARXJU9J"
CACHE_TABLE       = "trackhaul-dev-rag-cache"

# EU cross-region inference profile — never use a bare model ID directly
INFERENCE_PROFILE_ARN = (
    "arn:aws:bedrock:eu-central-1:281136219737:"
    "inference-profile/eu.anthropic.claude-sonnet-4-5-20250929-v1:0"
)

# Number of KB chunks to retrieve per query
KB_TOP_K = 5

# TTL strategy
TTL_STATIC_DOCS = 86400   # 24 h — maintenance manuals, fault codes
TTL_SEMI_LIVE   = 3600    # 1 h  — maintenance history
TTL_LIVE        = 0       # No cache — live event/anomaly queries

# Keywords that signal live data — bypass cache entirely
LIVE_KEYWORDS = [
    "today", "this week", "current", "now",
    "anomaly", "anomalies", "incident",
]

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# AWS clients
# ---------------------------------------------------------------------------

bedrock_agent   = boto3.client("bedrock-agent-runtime", region_name=REGION)
bedrock_runtime = boto3.client("bedrock-runtime", region_name=REGION)
dynamodb        = boto3.resource("dynamodb", region_name=REGION)
cache_table     = dynamodb.Table(CACHE_TABLE)

# ---------------------------------------------------------------------------
# Cache helpers  (unchanged from Day 25)
# ---------------------------------------------------------------------------

def hash_query(query: str) -> str:
    """Stable SHA256 hash of normalised query string."""
    return hashlib.sha256(query.strip().lower().encode()).hexdigest()


def is_live_query(query: str) -> bool:
    """Return True if query contains live-data keywords — skip cache."""
    q = query.lower()
    return any(kw in q for kw in LIVE_KEYWORDS)


def get_ttl(query: str) -> int:
    """Return appropriate TTL in seconds based on query content."""
    if is_live_query(query):
        return TTL_LIVE
    if "maintenance history" in query.lower():
        return TTL_SEMI_LIVE
    return TTL_STATIC_DOCS


def cache_get(query_hash: str) -> dict | None:
    """Return cached item if present, else None. Cache failures never break retrieval."""
    try:
        response = cache_table.get_item(Key={"query_hash": query_hash})
        item = response.get("Item")
        if item:
            logger.info("[CACHE] HIT")
            return item
    except Exception as e:
        # Degraded mode — log and continue without cache
        logger.warning(f"[CACHE] Read error — bypassing cache: {e}")
    return None


def cache_set(
    query_hash: str,
    query: str,
    answer: str,
    sources: list,
    contract: str,
    prompt_version: str,
    ttl: int,
):
    """Write answer to cache with TTL. No-op for live queries (ttl=0)."""
    if ttl == 0:
        logger.info("[CACHE] Live query — skipping cache write")
        return
    try:
        cache_table.put_item(Item={
            "query_hash":     query_hash,
            "query":          query,
            "answer":         answer,
            "sources":        json.dumps(sources),
            "contract":       contract,
            "prompt_version": prompt_version,
            "expires_at":     int(time.time()) + ttl,
            "cached_at":      int(time.time()),
        })
        logger.info(f"[CACHE] Written — TTL {ttl}s, contract {contract} v{prompt_version}")
    except Exception as e:
        logger.warning(f"[CACHE] Write error — continuing without cache: {e}")


# ---------------------------------------------------------------------------
# Retrieval — Bedrock KB (chunks only, no generation)
# ---------------------------------------------------------------------------

def retrieve_chunks(query: str) -> tuple[str, list]:
    """
    Retrieve top-K chunks from the Bedrock Knowledge Base.
    Returns (formatted_context_string, list_of_source_uris).

    Uses retrieve() not retrieve_and_generate() so we control
    the generation step via our own prompt contracts.
    """
    logger.info(f"[KB] Retrieving top {KB_TOP_K} chunks")

    response = bedrock_agent.retrieve(
        knowledgeBaseId=KNOWLEDGE_BASE_ID,
        retrievalQuery={"text": query},
        retrievalConfiguration={
            "vectorSearchConfiguration": {
                "numberOfResults": KB_TOP_K,
            }
        },
    )

    results = response.get("retrievalResults", [])
    if not results:
        logger.warning("[KB] No chunks returned for query")
        return "", []

    # Build a single context string from all retrieved chunks
    context_parts = []
    sources = []
    for i, result in enumerate(results, start=1):
        content = result.get("content", {}).get("text", "").strip()
        uri = (
            result.get("location", {})
            .get("s3Location", {})
            .get("uri", "unknown")
        )
        score = result.get("score", 0)

        context_parts.append(f"[Source {i} | score: {score:.3f}]\n{content}")
        if uri not in sources:
            sources.append(uri)

    context = "\n\n---\n\n".join(context_parts)
    logger.info(f"[KB] Retrieved {len(results)} chunks from {len(sources)} source(s)")
    return context, sources


# ---------------------------------------------------------------------------
# Generation — Bedrock converse API via prompt contract
# ---------------------------------------------------------------------------

def call_bedrock(query: str, context: str, contract: str) -> dict:
    """
    Build prompt payload from PromptManager and call Bedrock converse API.

    Args:
        query:    User query or anomaly/incident data string
        context:  Formatted RAG context from retrieve_chunks()
        contract: Prompt contract name (fleet-query, fault-diagnosis, etc.)

    Returns:
        Dict with response text, contract metadata, and token counts
    """
    pm = PromptManager()
    payload = pm.build_payload(contract=contract, query=query, context=context)
    version_info = pm.get_version_info(contract)

    logger.info(
        f"[BEDROCK] Calling converse — contract: {contract} "
        f"v{version_info['version']}, profile: {INFERENCE_PROFILE_ARN}"
    )

    response = bedrock_runtime.converse(
        modelId=INFERENCE_PROFILE_ARN,
        system=[{"text": payload["system"]}],
        messages=payload["messages"],
        inferenceConfig={
            "maxTokens": payload["max_tokens"],
            "temperature": payload["temperature"],
        },
    )

    output_text = response["output"]["message"]["content"][0]["text"]
    usage = response.get("usage", {})
    input_tokens  = usage.get("inputTokens", 0)
    output_tokens = usage.get("outputTokens", 0)

    logger.info(
        f"[BEDROCK] Tokens — input: {input_tokens}, output: {output_tokens}, "
        f"total: {input_tokens + output_tokens}"
    )

    return {
        "response":       output_text,
        "contract":       contract,
        "prompt_version": payload["contract_version"],
        "input_tokens":   input_tokens,
        "output_tokens":  output_tokens,
    }


# ---------------------------------------------------------------------------
# Main retrieval entry point
# ---------------------------------------------------------------------------

def query_fleet(user_query: str, contract: str = "fleet-query") -> dict:
    """
    Cache-aware RAG retrieval with prompt contract generation.

    Args:
        user_query: Natural language query or structured data string
        contract:   Prompt contract to use for generation

    Returns:
        Dict with answer, sources, cache status, token usage
    """
    logger.info(f"[QUERY] contract={contract} | query={user_query}")

    query_hash = hash_query(user_query)
    ttl        = get_ttl(user_query)

    # Step 1 — check cache (skip entirely for live queries)
    if ttl > 0:
        cached = cache_get(query_hash)
        if cached:
            return {
                "answer":         cached["answer"],
                "sources":        json.loads(cached.get("sources", "[]")),
                "contract":       cached.get("contract", "unknown"),
                "prompt_version": cached.get("prompt_version", "unknown"),
                "cached":         True,
                "input_tokens":   0,
                "output_tokens":  0,
            }

    # Step 2 — retrieve chunks from KB
    context, sources = retrieve_chunks(user_query)

    if not context:
        return {
            "answer":         "Insufficient data in the knowledge base to answer this query.",
            "sources":        [],
            "contract":       contract,
            "prompt_version": "n/a",
            "cached":         False,
            "input_tokens":   0,
            "output_tokens":  0,
        }

    # Step 3 — generate answer via prompt contract
    result = call_bedrock(query=user_query, context=context, contract=contract)

    # Step 4 — write to cache
    cache_set(
        query_hash=query_hash,
        query=user_query,
        answer=result["response"],
        sources=sources,
        contract=contract,
        prompt_version=result["prompt_version"],
        ttl=ttl,
    )

    return {
        "answer":         result["response"],
        "sources":        sources,
        "contract":       contract,
        "prompt_version": result["prompt_version"],
        "cached":         False,
        "input_tokens":   result["input_tokens"],
        "output_tokens":  result["output_tokens"],
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args():
    parser = argparse.ArgumentParser(
        description="TrackHaul RAG retrieval — cache-aware, prompt contract driven"
    )
    parser.add_argument(
        "--query",
        required=True,
        help="Natural language query or structured data string",
    )
    parser.add_argument(
        "--contract",
        default="fleet-query",
        choices=["fleet-query", "fault-diagnosis", "anomaly-explanation", "incident-summary"],
        help="Prompt contract to use (default: fleet-query)",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()

    result = query_fleet(user_query=args.query, contract=args.contract)

    print("\n" + "=" * 60)
    print(f"CONTRACT : {result['contract']} v{result['prompt_version']}")
    print(f"CACHED   : {result['cached']}")
    print(f"TOKENS   : input={result['input_tokens']} output={result['output_tokens']}")
    print(f"SOURCES  : {result['sources']}")
    print("-" * 60)
    print(result["answer"])
    print("=" * 60)