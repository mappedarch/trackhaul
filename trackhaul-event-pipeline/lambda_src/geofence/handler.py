import json
import logging
import os
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sfn_client = boto3.client("stepfunctions")
STATE_MACHINE_ARN = os.environ["STATE_MACHINE_ARN"]

def handler(event, context):
    """
    Geofence consumer — processes geofence breach events from SQS.
    CRITICAL and default severity events trigger the incident workflow.
    No PII in payload — truck_id only.
    """
    batch_item_failures = []

    for record in event["Records"]:
        message_id = record["messageId"]
        try:
            body = json.loads(record["body"])
            detail = body.get("detail", {})

            truck_id   = detail.get("truck_id")
            zone       = detail.get("zone_id")
            breach_type = detail.get("breach_type")
            severity   = detail.get("severity", "CRITICAL")
            fault_code = detail.get("fault_code", "GEO-BREACH")

            logger.info(
                "Geofence breach",
                extra={
                    "truck_id":    truck_id,
                    "zone_id":     zone,
                    "breach_type": breach_type,
                    "severity":    severity,
                }
            )

            # Trigger incident workflow for all geofence breaches
            sfn_client.start_execution(
                stateMachineArn=STATE_MACHINE_ARN,
                # Unique execution name — truck + message ID prevents duplicates
                name=f"{truck_id}-{message_id[:8]}",
                input=json.dumps({
                    "truck_id":   truck_id,
                    "fault_code": fault_code,
                    "severity":   severity,
                    "zone_id":    zone,
                    "source":     "GEOFENCE"
                })
            )

            logger.info(f"Incident workflow triggered for truck {truck_id}")

        except Exception as e:
            logger.error(f"Failed to process message {message_id}: {e}")
            batch_item_failures.append({"itemIdentifier": message_id})

    return {"batchItemFailures": batch_item_failures}