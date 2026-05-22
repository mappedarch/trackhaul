import json
import logging
import os
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sfn_client = boto3.client("stepfunctions")
STATE_MACHINE_ARN = os.environ["STATE_MACHINE_ARN"]

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
    Maintenance consumer — processes fault codes and maintenance trigger events.
    CRITICAL severity events trigger the incident workflow.
    No PII — truck_id only.
    """
    records, detail = extract_detail(event)

    # SQS path — batch processing with partial failure support
    if records:
        batch_item_failures = []
        for record in records:
            message_id = record["messageId"]
            try:
                body = json.loads(record["body"])
                detail = body.get("detail", {})
                process_event(detail, message_id)
            except Exception as e:
                logger.error(f"Failed to process message {message_id}: {e}")
                batch_item_failures.append({"itemIdentifier": message_id})
        return {"batchItemFailures": batch_item_failures}

    # Step Functions path — single event, raise on failure so SFN catches it
    process_event(detail, None)
    return {"status": "ok", "truck_id": detail.get("truck_id"), "severity": detail.get("severity")}


def process_event(detail, message_id):
    truck_id    = detail.get("truck_id")
    fault_code  = detail.get("fault_code")
    severity    = detail.get("severity", "CRITICAL")
    odometer_km = detail.get("odometer_km")

    logger.info(
        "Maintenance event",
        extra={
            "truck_id":    truck_id,
            "fault_code":  fault_code,
            "severity":    severity,
            "odometer_km": odometer_km,
        }
    )

    # Trigger incident workflow for CRITICAL faults only
    if severity == "CRITICAL" and message_id:
        sfn_client.start_execution(
            stateMachineArn=STATE_MACHINE_ARN,
            # Unique execution name — truck + message ID prevents duplicates
            name=f"{truck_id}-{message_id[:8]}",
            input=json.dumps({
                "truck_id":   truck_id,
                "fault_code": fault_code,
                "severity":   severity,
                "source":     "MAINTENANCE"
            })
        )
        logger.info(f"Incident workflow triggered for truck {truck_id}")