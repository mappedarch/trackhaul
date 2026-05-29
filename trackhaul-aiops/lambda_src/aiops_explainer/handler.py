import base64
import json
import boto3
import os
import logging
import re
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)

bedrock = boto3.client("bedrock-runtime", region_name=os.environ["BEDROCK_REGION"])

MODEL_ID = os.environ["BEDROCK_MODEL_ID"]
LOG_GROUP = os.environ["EXPLANATION_LOG_GROUP"]


def lambda_handler(event, context):
    """
    Triggered by EventBridge anomaly events from trackhaul-dev-fleet-events bus.
    Calls Bedrock to generate a structured explanation of the anomaly.
    No PII enters the prompt — truck_id and sensor_data only.
    """
    detail = event.get("detail", {})
    truck_id = detail.get("truck_id", "UNKNOWN")
    event_type = detail.get("event_type", "UNKNOWN")
    region = detail.get("region", "UNKNOWN")
    timestamp = detail.get("timestamp", datetime.now(timezone.utc).isoformat())
    sensor_data = detail.get("sensor_data", {})

    logger.info(f"AIOps explainer triggered: truck_id={truck_id} event_type={event_type}")

    prompt = build_prompt(truck_id, event_type, region, timestamp, sensor_data)

    try:
        explanation = invoke_bedrock(prompt)
        log_explanation(truck_id, event_type, region, timestamp, sensor_data, explanation)
        logger.info(f"Explanation generated for truck_id={truck_id}")
        return {"statusCode": 200, "truck_id": truck_id, "explanation": explanation}

    except Exception as e:
        logger.error(f"Bedrock invocation failed for truck_id={truck_id}: {e}")
        raise


def build_prompt(truck_id, event_type, region, timestamp, sensor_data):
    """
    Builds a structured prompt. No PII — truck_id and sensor readings only.
    Instructs the model to return a structured JSON explanation.
    """
    sensor_str = json.dumps(sensor_data, indent=2)

    return f"""You are an expert fleet operations analyst for a European logistics company.

A telemetry anomaly has been detected. Analyse the sensor data and provide a structured explanation.

Anomaly details:
- Truck ID: {truck_id}
- Event type: {event_type}
- Fleet region: {region}
- Timestamp: {timestamp}
- Sensor readings:
{sensor_str}

Respond ONLY with a JSON object in this exact format with no additional text, no markdown, no code fences:
{{
  "what_happened": "one sentence describing the anomaly",
  "likely_cause": "one sentence on the most probable root cause based on sensor data",
  "similar_pattern": "one sentence describing what similar past incidents typically indicate",
  "recommended_action": "one sentence on the immediate recommended action",
  "urgency": "low | medium | high | critical"
}}"""


def invoke_bedrock(prompt):
    """Invoke Bedrock Claude model and return parsed explanation."""
    body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 512,
        "messages": [
            {"role": "user", "content": prompt}
        ]
    }

    response = bedrock.invoke_model(
        modelId=MODEL_ID,
        contentType="application/json",
        accept="application/json",
        body=json.dumps(body)
    )

    response_body = json.loads(response["body"].read())
    raw_text = response_body["content"][0]["text"].strip()

    logger.info(f"Raw Bedrock response: {raw_text}")

    # Strip markdown code fences if present
    raw_text = re.sub(r"^```(?:json)?\s*", "", raw_text)
    raw_text = re.sub(r"\s*```$", "", raw_text)
    raw_text = raw_text.strip()

    parsed = json.loads(raw_text)
    return parsed


def log_explanation(truck_id, event_type, region, timestamp, sensor_data, explanation):
    """
    Write structured explanation log to CloudWatch.
    No PII — truck_id only. No driver names, no GPS coordinates.
    """
    log_entry = {
        "truck_id": truck_id,
        "event_type": event_type,
        "region": region,
        "timestamp": timestamp,
        "sensor_data": sensor_data,
        "explanation": explanation,
        "logged_at": datetime.now(timezone.utc).isoformat()
    }

    logger.info(f"AIOPS_EXPLANATION: {json.dumps(log_entry)}")
