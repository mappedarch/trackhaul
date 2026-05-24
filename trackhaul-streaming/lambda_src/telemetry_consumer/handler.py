import base64
import json
import boto3
import os
import logging
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# EventBridge client — initialised outside handler for connection reuse
events_client = boto3.client("events", region_name=os.environ["AWS_REGION"])

ANOMALY_EVENT_BUS = os.environ["ANOMALY_EVENT_BUS_NAME"]
ANOMALY_TYPES = {"fuel_anomaly", "engine_fault", "harsh_braking", "geofence_breach"}


def lambda_handler(event, context):
    """
    EFO consumer for the trackhaul-telemetry Kinesis stream.
    Each record is a base64-encoded JSON telemetry payload.
    Anomaly events are forwarded to EventBridge for downstream processing.
    """
    records = event.get("Records", [])
    logger.info(f"Received {len(records)} records from Kinesis EFO")

    anomaly_entries = []

    for record in records:
        try:
            # Decode base64 payload from Kinesis
            raw = base64.b64decode(record["kinesis"]["data"]).decode("utf-8")
            payload = json.loads(raw)

            truck_id = payload.get("truck_id", "UNKNOWN")
            event_type = payload.get("event_type", "UNKNOWN")
            region = payload.get("region", "UNKNOWN")
            timestamp = payload.get("timestamp", datetime.now(timezone.utc).isoformat())

            logger.info(f"truck_id={truck_id} event_type={event_type} region={region}")

            # Forward anomalies to EventBridge — no PII in payload
            if event_type in ANOMALY_TYPES:
                anomaly_entries.append(
                    build_eventbridge_entry(truck_id, event_type, region, timestamp, payload)
                )

        except (KeyError, json.JSONDecodeError) as e:
            # Log and continue — do not raise, prevents whole batch failure
            logger.error(f"Failed to parse record: {e}")

    # Batch-publish anomalies to EventBridge (max 10 per PutEvents call)
    if anomaly_entries:
        publish_to_eventbridge(anomaly_entries)

    return {"statusCode": 200, "processedRecords": len(records)}


def build_eventbridge_entry(truck_id, event_type, region, timestamp, payload):
    """Build an EventBridge PutEvents entry. No PII — truck_id only."""
    detail = {
        "truck_id": truck_id,
        "event_type": event_type,
        "region": region,
        "timestamp": timestamp,
        # Include numeric sensor fields only — no driver name, no GPS
        "sensor_data": {
            k: v for k, v in payload.items()
            if k not in {"truck_id", "event_type", "region", "timestamp", "driver_id", "gps"}
        },
    }
    return {
        "Source": "trackhaul.telemetry",
        "DetailType": event_type,
        "Detail": json.dumps(detail),
        "EventBusName": ANOMALY_EVENT_BUS,
    }


def publish_to_eventbridge(entries):
    """Publish in batches of 10 — EventBridge PutEvents limit."""
    for i in range(0, len(entries), 10):
        batch = entries[i : i + 10]
        response = events_client.put_events(Entries=batch)
        failed = response.get("FailedEntryCount", 0)
        if failed:
            logger.error(f"EventBridge: {failed} entries failed in batch starting at {i}")
        else:
            logger.info(f"EventBridge: published {len(batch)} anomaly events")