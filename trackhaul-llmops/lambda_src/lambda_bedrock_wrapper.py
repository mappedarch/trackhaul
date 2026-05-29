"""
TrackHaul LLM Bedrock Wrapper
------------------------------
Single instrumentation point for all Bedrock invocations.
Responsibilities:
  - Fetch active prompt version from SSM via localhost extension cache
  - Call Bedrock InvokeModel
  - Emit structured log entry to CloudWatch (no PII)
  - Return response to caller

Simulation mode: set SIMULATION_MODE=true to skip Bedrock call.
Used for Terraform apply and integration testing without incurring token cost.
"""

import json
import os
import urllib.request
import urllib.parse
import boto3
import logging

# -------------------------------------------------------
# Logger — structured JSON output, no PII
# -------------------------------------------------------
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# -------------------------------------------------------
# Environment variables
# -------------------------------------------------------
BEDROCK_MODEL_ID          = os.environ["BEDROCK_MODEL_ID"]
SSM_PROMPT_PARAMETER_NAME = os.environ["SSM_PROMPT_PARAMETER_NAME"]
SIMULATION_MODE           = os.environ.get("SIMULATION_MODE", "false").lower() == "true"
ENVIRONMENT               = os.environ.get("ENVIRONMENT", "dev")

# Extension listens on localhost:2773
EXTENSION_BASE_URL = "http://localhost:2773"

bedrock = boto3.client("bedrock-runtime", region_name="eu-central-1")


def fetch_prompt_from_extension(parameter_name: str) -> str:
    """
    Fetch SSM parameter value via the Lambda extension localhost endpoint.
    The extension caches the value for SSM_PARAMETER_STORE_TTL seconds.
    URL-encode the parameter name — forward slashes must be encoded.
    """
    encoded_name = urllib.parse.quote(parameter_name, safe="")
    url = f"{EXTENSION_BASE_URL}/systemsmanager/parameters/get?name={encoded_name}"

    # Header required — extension validates the session token
    session_token = os.environ.get("AWS_SESSION_TOKEN", "")

    req = urllib.request.Request(
        url,
        headers={"X-Aws-Parameters-Secrets-Token": session_token}
    )

    with urllib.request.urlopen(req) as response:
        body = json.loads(response.read().decode())
        return body["Parameter"]["Value"]


def invoke_bedrock(prompt: str, query: str) -> dict:
    """
    Call Bedrock InvokeModel with the system prompt and user query.
    Returns the response body as a dict.
    """
    request_body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 1024,
        "system": prompt,
        "messages": [
            {
                "role": "user",
                "content": query
            }
        ]
    }

    response = bedrock.invoke_model(
        modelId=BEDROCK_MODEL_ID,
        contentType="application/json",
        accept="application/json",
        body=json.dumps(request_body)
    )

    return json.loads(response["body"].read())


def build_log_entry(truck_id: str, query_type: str, input_tokens: int,
                    output_tokens: int, latency_ms: int, simulated: bool) -> dict:
    """
    Structured log entry — no PII.
    truck_id is the only vehicle-level identifier permitted.
    """
    return {
        "environment":    ENVIRONMENT,
        "truck_id":       truck_id,
        "query_type":     query_type,
        "model_id":       BEDROCK_MODEL_ID,
        "input_tokens":   input_tokens,
        "output_tokens":  output_tokens,
        "latency_ms":     latency_ms,
        "simulated":      simulated
    }


def handler(event, context):
    """
    Lambda handler.

    Expected event shape:
    {
        "query":      "Which trucks had fuel anomalies this week?",
        "query_type": "fuel_anomaly",
        "truck_id":   "TH-4821"
    }
    """
    import time

    query      = event.get("query", "")
    query_type = event.get("query_type", "unknown")
    truck_id   = event.get("truck_id", "unknown")

    start_ms = int(time.time() * 1000)

    # -------------------------------------------------------
    # Simulation mode — skip Bedrock, return synthetic response
    # -------------------------------------------------------
    if SIMULATION_MODE:
        logger.info(json.dumps(build_log_entry(
            truck_id, query_type, 0, 0, 0, simulated=True
        )))
        return {
            "statusCode": 200,
            "simulated":  True,
            "answer":     "Simulation mode active — no Bedrock call made."
        }

    # -------------------------------------------------------
    # Fetch active prompt via SSM extension cache
    # -------------------------------------------------------
    try:
        active_version = fetch_prompt_from_extension(SSM_PROMPT_PARAMETER_NAME)
    except Exception as e:
        logger.error(json.dumps({"error": "ssm_fetch_failed", "detail": str(e)}))
        raise

    # -------------------------------------------------------
    # Invoke Bedrock
    # -------------------------------------------------------
    try:
        response_body = invoke_bedrock(prompt=active_version, query=query)
    except Exception as e:
        logger.error(json.dumps({"error": "bedrock_invoke_failed", "detail": str(e)}))
        raise

    end_ms = int(time.time() * 1000)

    # -------------------------------------------------------
    # Extract token usage from response metadata
    # -------------------------------------------------------
    usage        = response_body.get("usage", {})
    input_tokens = usage.get("input_tokens", 0)
    output_tokens = usage.get("output_tokens", 0)
    answer       = response_body.get("content", [{}])[0].get("text", "")

    # -------------------------------------------------------
    # Emit structured log — no PII
    # -------------------------------------------------------
    logger.info(json.dumps(build_log_entry(
        truck_id, query_type, input_tokens, output_tokens,
        latency_ms=end_ms - start_ms, simulated=False
    )))

    return {
        "statusCode":   200,
        "simulated":    False,
        "answer":       answer,
        "input_tokens": input_tokens,
        "output_tokens": output_tokens
    }