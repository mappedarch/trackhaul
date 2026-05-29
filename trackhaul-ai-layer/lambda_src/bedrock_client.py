"""
bedrock_client.py — Regional failover and circuit breaker for Bedrock invocations.
Owns all Bedrock invoke_model calls. fleet_intelligence_handler imports from here.

Failover chain:
  Primary:    eu-central-1 → Claude Sonnet
  Fallback 1: eu-west-1    → Claude Sonnet
  Fallback 2: eu-west-1    → Claude Haiku  (degraded but functional)

Circuit breaker:
  - Trips after 3 consecutive failures per region
  - State stored in DynamoDB — shared across all concurrent Lambda instances
  - Resets automatically after 60 seconds via DynamoDB TTL
"""

import json
import time
import logging
import os
import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ── Config ────────────────────────────────────────────────────────────────────
CIRCUIT_BREAKER_TABLE = os.environ.get("CIRCUIT_BREAKER_TABLE", "trackhaul-dev-circuit-breaker")
FAILURE_THRESHOLD     = int(os.environ.get("CB_FAILURE_THRESHOLD", "3"))
RESET_SECONDS         = int(os.environ.get("CB_RESET_SECONDS", "60"))

# Failover chain — order matters, never leave EU
FAILOVER_CHAIN = [
    {"region": "eu-central-1", "model_id": "eu.anthropic.claude-sonnet-4-5-20250929-v1:0", "tier": "primary"},
    {"region": "eu-west-1",    "model_id": "eu.anthropic.claude-sonnet-4-5-20250929-v1:0", "tier": "fallback-1"},
    {"region": "eu-west-1",    "model_id": "eu.anthropic.claude-haiku-4-5-20251001-v1:0",  "tier": "fallback-2"},
]

# ── DynamoDB client ───────────────────────────────────────────────────────────
_dynamodb = boto3.resource("dynamodb", region_name="eu-central-1")
_cb_table = _dynamodb.Table(CIRCUIT_BREAKER_TABLE)


# ── Circuit breaker state ─────────────────────────────────────────────────────
def _get_cb_state(region: str) -> dict:
    """
    Read circuit breaker state for a region from DynamoDB.
    Returns default open state if no record exists.
    """
    try:
        response = _cb_table.get_item(Key={"region": region})
        return response.get("Item", {"region": region, "failures": 0, "tripped": False})
    except ClientError as e:
        # If DynamoDB is unavailable, fail open — don't block all AI traffic
        logger.warning(f"CB state read failed for {region}: {e}")
        return {"region": region, "failures": 0, "tripped": False}


def _record_failure(region: str) -> None:
    """
    Increment failure count for a region.
    Trips the circuit breaker if threshold is reached.
    Sets TTL so DynamoDB auto-resets after RESET_SECONDS.
    """
    try:
        reset_at = int(time.time()) + RESET_SECONDS
        _cb_table.update_item(
            Key={"region": region},
            UpdateExpression="SET failures = if_not_exists(failures, :zero) + :inc, reset_at = :reset",
            ExpressionAttributeValues={":zero": 0, ":inc": 1, ":reset": reset_at},
        )
        state = _get_cb_state(region)
        if state.get("failures", 0) >= FAILURE_THRESHOLD:
            _cb_table.update_item(
                Key={"region": region},
                UpdateExpression="SET tripped = :t, reset_at = :reset",
                ExpressionAttributeValues={":t": True, ":reset": reset_at},
            )
            logger.warning(f"Circuit breaker TRIPPED for region {region}")
    except ClientError as e:
        logger.warning(f"CB state write failed for {region}: {e}")


def _record_success(region: str) -> None:
    """Reset circuit breaker state on successful invocation."""
    try:
        _cb_table.put_item(Item={"region": region, "failures": 0, "tripped": False})
    except ClientError as e:
        logger.warning(f"CB state reset failed for {region}: {e}")


def _is_tripped(region: str) -> bool:
    """Returns True if the circuit breaker is tripped for this region."""
    state = _get_cb_state(region)
    return state.get("tripped", False)


def _invoke(region: str, model_id: str, prompt: str) -> str:
    """
    Single Bedrock invocation attempt against a specific region and model.
    Raises on any failure — caller handles retry logic.
    """
    client = boto3.client("bedrock-runtime", region_name=region)
    body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 512,
        "messages": [{"role": "user", "content": prompt}],
    }
    response = client.invoke_model(
        modelId=model_id,
        contentType="application/json",
        accept="application/json",
        body=json.dumps(body),
    )
    result = json.loads(response["body"].read())
    return result["content"][0]["text"]

# ── Public interface ──────────────────────────────────────────────────────────
def invoke_with_failover(prompt: str, preferred_model_id: str = None, preferred_region: str = None) -> dict:
    """
    Attempt Bedrock invocation across the failover chain.
    Skips tripped regions. Records failures and successes.
    Returns dict with answer, region used, tier used, and whether fallback occurred.
    preferred_model_id — passed from model_router, used at primary tier only.
    preferred_region   — passed from model_router, used at primary tier only.
    If None, chain defaults are used throughout.
    """
    last_error = None
    for i, target in enumerate(FAILOVER_CHAIN):
        region   = preferred_region   if i == 0 and preferred_region   else target["region"]
        model_id = preferred_model_id if i == 0 and preferred_model_id else target["model_id"]
        tier     = target["tier"]
        if _is_tripped(region) and tier == "primary":
            logger.info(f"Circuit breaker tripped for {region} — skipping to fallback")
            continue
        try:
            logger.info(f"Invoking Bedrock | region={region} model={model_id} tier={tier}")
            answer = _invoke(region, model_id, prompt)
            _record_success(region)
            return {
                "answer":            answer,
                "region_used":       region,
                "tier_used":         tier,
                "fallback_occurred": tier != "primary",
            }
        except Exception as e:
            logger.error(f"Bedrock invocation failed | region={region} tier={tier} error={e}")
            _record_failure(region)
            last_error = e
            continue
    raise RuntimeError(f"All Bedrock failover targets exhausted. Last error: {last_error}")