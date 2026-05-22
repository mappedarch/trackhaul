import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def extract_detail(event):
    """
    Normalise event from either SQS or Step Functions invocation.
    SQS wraps payload in Records[].body — Step Functions passes raw JSON.
    """
    if "Records" in event:
        body = json.loads(event["Records"][0]["body"])
        return event["Records"], body.get("detail", {})
    else:
        return None, event

def handler(event, context):
    """
    Fuel anomaly consumer — processes fuel anomaly events.
    No PII in payload — truck_id only.
    """
    records, detail = extract_detail(event)

    if records:
        batch_item_failures = []
        for record in records:
            message_id = record["messageId"]
            try:
                body = json.loads(record["body"])
                detail = body.get("detail", {})
                process_event(detail)
            except Exception as e:
                logger.error(f"Failed to process message {message_id}: {e}")
                batch_item_failures.append({"itemIdentifier": message_id})
        return {"batchItemFailures": batch_item_failures}

    process_event(detail)
    return {"status": "ok", "truck_id": detail.get("truck_id"), "severity": detail.get("severity")}


def process_event(detail):
    truck_id           = detail.get("truck_id")
    anomaly_type       = detail.get("anomaly_type")       # e.g. EXCESS_CONSUMPTION
    fuel_delta_litres  = detail.get("fuel_delta_litres")
    region             = detail.get("region")

    logger.info(
        "Fuel anomaly detected",
        extra={
            "truck_id":          truck_id,
            "anomaly_type":      anomaly_type,
            "fuel_delta_litres": fuel_delta_litres,
            "region":            region,
        }
    )