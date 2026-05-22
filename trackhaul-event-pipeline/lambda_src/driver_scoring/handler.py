import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """
    Driver scoring consumer — processes driver behaviour events.
    Note: driver_id is omitted — truck_id only to comply with GDPR.
    """
    batch_item_failures = []

    for record in event["Records"]:
        message_id = record["messageId"]
        try:
            body = json.loads(record["body"])
            detail = body.get("detail", {})

            truck_id = detail.get("truck_id")
            event_type = detail.get("event_type")  # HARSH_BRAKE, HARSH_ACCEL, etc.
            severity = detail.get("severity")       # LOW, MEDIUM, HIGH
            score_delta = detail.get("score_delta") # points change

            logger.info(
                "Driver scoring event",
                extra={
                    "truck_id": truck_id,
                    "event_type": event_type,
                    "severity": severity,
                    "score_delta": score_delta,
                }
            )

        except Exception as e:
            logger.error(f"Failed to process message {message_id}: {e}")
            batch_item_failures.append({"itemIdentifier": message_id})

    return {"batchItemFailures": batch_item_failures}