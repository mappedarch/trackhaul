"""
TrackHaul LLM Bedrock Wrapper
------------------------------
Single instrumentation point for all Bedrock invocations.
Responsibilities:
  - Fetch active prompt version from SSM via localhost extension cache
  - Call Bedrock InvokeModel
  - Emit structured log entry to CloudWatch (no PII)
  - Emit custom CloudWatch metrics — Tier 1 operational and Tier 2 cost
  - Write structured interaction log to custom log group
  - Return response to caller

Simulation mode: set SIMULATION_MODE=true to skip Bedrock call.
Used for Terraform apply and integration testing without incurring token cost.
"""

import json
import os
import time
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

EXTENSION_BASE_URL    = "http://localhost:2773"
METRICS_NAMESPACE     = "TrackHaul/LLMOps"
COST_METRICS_NAMESPACE = "TrackHaul/LLMCost"
INTERACTION_LOG_GROUP = f"/trackhaul/llm/interactions/{ENVIRONMENT}"

bedrock    = boto3.client("bedrock-runtime", region_name="eu-central-1")
cloudwatch = boto3.client("cloudwatch", region_name="eu-central-1")
logs       = boto3.client("logs", region_name="eu-central-1")


def fetch_prompt_from_extension(parameter_name: str) -> str:
    """
    Fetch SSM parameter value via the Lambda extension localhost endpoint.
    The extension caches the value for SSM_PARAMETER_STORE_TTL seconds.
    """
    encoded_name = urllib.parse.quote(parameter_name, safe="")
    url = f"{EXTENSION_BASE_URL}/systemsmanager/parameters/get?name={encoded_name}"
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
        "messages": [{"role": "user", "content": query}]
    }

    response = bedrock.invoke_model(
        modelId=BEDROCK_MODEL_ID,
        contentType="application/json",
        accept="application/json",
        body=json.dumps(request_body)
    )

    return json.loads(response["body"].read())


def emit_metrics(truck_id: str, query_type: str, fleet_region: str,
                 input_tokens: int, output_tokens: int, latency_ms: float,
                 prompt_version: str,
                 is_error: bool, is_throttled: bool,
                 response_length: int = 0) -> None:
    """
    Emit Tier 1 operational metrics and Tier 2 cost metrics to CloudWatch.
    Two separate put_metric_data calls — different namespaces per strategy.

    Tier 1 — TrackHaul/LLMOps  — alarm on these
    Tier 2 — TrackHaul/LLMCost — report and budget on these
    """

    # -------------------------------------------------------
    # Tier 1 — Operational metrics
    # Dimensions: model_id and query_type per strategy Section 3
    # -------------------------------------------------------
    cloudwatch.put_metric_data(
        Namespace=METRICS_NAMESPACE,
        MetricData=[
            {
                "MetricName": "InvocationLatency",
                "Dimensions": [
                    {"Name": "model_id",    "Value": BEDROCK_MODEL_ID},
                    {"Name": "query_type",  "Value": query_type}
                ],
                "Value": latency_ms,
                "Unit":  "Milliseconds"
            },
            {
                "MetricName": "InvocationErrorCount",
                "Dimensions": [
                    {"Name": "model_id", "Value": BEDROCK_MODEL_ID}
                ],
                "Value": 1 if is_error else 0,
                "Unit":  "Count"
            },
            {
                "MetricName": "ThrottledRequestCount",
                "Dimensions": [
                    {"Name": "model_id", "Value": BEDROCK_MODEL_ID}
                ],
                "Value": 1 if is_throttled else 0,
                "Unit":  "Count"
            },
            {
                "MetricName": "InputTokensPerRequest",
                "Dimensions": [
                    {"Name": "model_id",   "Value": BEDROCK_MODEL_ID},
                    {"Name": "query_type", "Value": query_type}
                ],
                "Value": input_tokens,
                "Unit":  "Count"
            },
            {
                "MetricName": "InvocationsTotal",
                "Dimensions": [
                    {"Name": "model_id",   "Value": BEDROCK_MODEL_ID},
                    {"Name": "query_type", "Value": query_type}
                ],
                "Value": 1,
                "Unit":  "Count"
            },
            {
                # Quality and drift metric
                # response_length is character count of the answer text
                # Tracked per prompt_version and query_type so drift can be
                # attributed to a specific prompt change
                "MetricName": "ResponseLengthMean",
                "Dimensions": [
                    {"Name": "prompt_version", "Value": prompt_version},
                    {"Name": "query_type",     "Value": query_type}
                ],
                "Value": response_length,
                "Unit":  "Count"
            }
        ]
    )

    # -------------------------------------------------------
    # Tier 2 — Cost governance metrics
    # Dimensions: truck_id, model_id, fleet_region per strategy Section 3
    # Input and output tokens always separate — different pricing per model
    # -------------------------------------------------------
    cloudwatch.put_metric_data(
        Namespace=COST_METRICS_NAMESPACE,
        MetricData=[
            {
                "MetricName": "InputTokensTotal",
                "Dimensions": [
                    {"Name": "truck_id",      "Value": truck_id},
                    {"Name": "model_id",      "Value": BEDROCK_MODEL_ID},
                    {"Name": "fleet_region",  "Value": fleet_region}
                ],
                "Value": input_tokens,
                "Unit":  "Count"
            },
            {
                "MetricName": "OutputTokensTotal",
                "Dimensions": [
                    {"Name": "truck_id",      "Value": truck_id},
                    {"Name": "model_id",      "Value": BEDROCK_MODEL_ID},
                    {"Name": "fleet_region",  "Value": fleet_region}
                ],
                "Value": output_tokens,
                "Unit":  "Count"
            },
            {
                "MetricName": "InvocationsTotal",
                "Dimensions": [
                    {"Name": "query_type",   "Value": query_type},
                    {"Name": "fleet_region", "Value": fleet_region}
                ],
                "Value": 1,
                "Unit":  "Count"
            }
        ]
    )


def write_interaction_log(log_entry: dict) -> None:
    """
    Write structured interaction log to the custom log group.
    This is separate from the Lambda runtime log group.
    Sequence token not required — CloudWatch accepts without it for new streams.
    """
    log_stream = f"{ENVIRONMENT}/fleet-assistant"

    # Create log stream if it does not exist — idempotent
    try:
        logs.create_log_stream(
            logGroupName=INTERACTION_LOG_GROUP,
            logStreamName=log_stream
        )
    except logs.exceptions.ResourceAlreadyExistsException:
        pass

    logs.put_log_events(
        logGroupName=INTERACTION_LOG_GROUP,
        logStreamName=log_stream,
        logEvents=[{
            "timestamp": int(time.time() * 1000),
            "message":   json.dumps(log_entry)
        }]
    )


def build_log_entry(truck_id: str, query_type: str, fleet_region: str,
                    input_tokens: int, output_tokens: int,
                    latency_ms: int, simulated: bool) -> dict:
    """
    Structured log entry — no PII.
    truck_id is the only vehicle-level identifier permitted.
    """
    return {
        "environment":   ENVIRONMENT,
        "truck_id":      truck_id,
        "query_type":    query_type,
        "fleet_region":  fleet_region,
        "model_id":      BEDROCK_MODEL_ID,
        "input_tokens":  input_tokens,
        "output_tokens": output_tokens,
        "latency_ms":    latency_ms,
        "simulated":     simulated
    }


def handler(event, context):
    """
    Lambda handler.

    Expected event shape:
    {
        "query":        "Which trucks had fuel anomalies this week?",
        "query_type":   "fault_lookup | fuel_anomaly | safety_score",
        "truck_id":     "TH-4821",
        "fleet_region": "DE | PL | NL"
    }
    """
    query        = event.get("query", "")
    query_type   = event.get("query_type", "unknown")
    truck_id     = event.get("truck_id", "unknown")
    fleet_region = event.get("fleet_region", "unknown")

    start_ms = int(time.time() * 1000)

    # -------------------------------------------------------
    # Simulation mode — skip Bedrock, return synthetic response
    # -------------------------------------------------------
    if SIMULATION_MODE:
        log_entry = build_log_entry(truck_id, query_type, fleet_region, 0, 0, 0, simulated=True)
        logger.info(json.dumps(log_entry))
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
        # Extract version label from SSM path e.g. /trackhaul/llmops/prompts/fleet-assistant/active
        # The active parameter holds the prompt text not a pointer — so we derive version from SSM_PROMPT_PARAMETER_NAME
        prompt_version = SSM_PROMPT_PARAMETER_NAME.split("/")[-1]  # yields "active" or "v1"
    except Exception as e:
        logger.error(json.dumps({"error": "ssm_fetch_failed", "detail": str(e)}))
        emit_metrics(truck_id, query_type, fleet_region, 0, 0, 0, "unknown", is_error=True, is_throttled=False)
        raise

    # -------------------------------------------------------
    # Invoke Bedrock
    # -------------------------------------------------------
    is_throttled = False
    try:
        response_body = invoke_bedrock(prompt=active_version, query=query)
    except bedrock.exceptions.ThrottlingException:
        is_throttled = True
        emit_metrics(truck_id, query_type, fleet_region, 0, 0, 0, prompt_version, is_error=True, is_throttled=True)
        raise
    except Exception as e:
        logger.error(json.dumps({"error": "bedrock_invoke_failed", "detail": str(e)}))
        emit_metrics(truck_id, query_type, fleet_region, 0, 0, 0, prompt_version, is_error=True, is_throttled=False)
        raise

    latency_ms    = int(time.time() * 1000) - start_ms
    usage         = response_body.get("usage", {})
    input_tokens  = usage.get("input_tokens", 0)
    output_tokens = usage.get("output_tokens", 0)
    answer        = response_body.get("content", [{}])[0].get("text", "")

    # -------------------------------------------------------
    # Emit metrics 
    # -------------------------------------------------------
    emit_metrics(
        truck_id, query_type, fleet_region,
        input_tokens, output_tokens, latency_ms,
        prompt_version=prompt_version,
        is_error=False, is_throttled=False,
        response_length=len(answer)   # character count — no PII, just length
    )

    # -------------------------------------------------------
    # Structured log — runtime log group via logger
    # -------------------------------------------------------
    log_entry = build_log_entry(
        truck_id, query_type, fleet_region,
        input_tokens, output_tokens, latency_ms, simulated=False
    )
    logger.info(json.dumps(log_entry))

    # -------------------------------------------------------
    # Write to custom interaction log group — separate concern
    # -------------------------------------------------------
    try:
        write_interaction_log(log_entry)
    except Exception as e:
        # Non-fatal — log the failure but do not fail the invocation
        logger.error(json.dumps({"error": "interaction_log_write_failed", "detail": str(e)}))

    return {
        "statusCode":   200,
        "simulated":    False,
        "answer":       answer,
        "input_tokens": input_tokens,
        "output_tokens": output_tokens
    }