"""
Token tracker for TrackHaul AI layer.
Records Bedrock token consumption per vehicle and per fleet to DynamoDB.
Uses atomic ADD to handle concurrent writes safely at high volume.
"""

import boto3
import os
import logging
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
cloudwatch = boto3.client("cloudwatch")

TABLE_NAME = os.environ["TOKEN_TRACKER_TABLE"]
NAMESPACE = "TrackHaul/AI"


def record_token_usage(truck_id: str, fleet_id: str, input_tokens: int, output_tokens: int, model_id: str):
    """
    Atomically increments token counters for a vehicle and its fleet.
    pk=VEHICLE#<truck_id>, sk=<YYYY-MM> for per-vehicle monthly totals.
    pk=FLEET#<fleet_id>,   sk=<YYYY-MM> for per-fleet monthly totals.
    """
    table = dynamodb.Table(TABLE_NAME)
    month_key = datetime.now(timezone.utc).strftime("%Y-%m")
    total_tokens = input_tokens + output_tokens

    # TTL: expire records after 90 days (for cost, not compliance — CloudWatch is the audit trail)
    expires_at = int(datetime.now(timezone.utc).timestamp()) + (90 * 86400)

    records = [
        {"pk": f"VEHICLE#{truck_id}", "sk": month_key},
        {"pk": f"FLEET#{fleet_id}",   "sk": month_key},
    ]

    for record in records:
        # Atomic ADD — safe under concurrent Lambda invocations
        table.update_item(
            Key=record,
            UpdateExpression="ADD input_tokens :i, output_tokens :o, total_tokens :t SET expires_at = if_not_exists(expires_at, :e), model_id = :m",
            ExpressionAttributeValues={
                ":i": input_tokens,
                ":o": output_tokens,
                ":t": total_tokens,
                ":e": expires_at,
                ":m": model_id,
            },
        )

    logger.info(f"Recorded {total_tokens} tokens for vehicle {truck_id} fleet {fleet_id}")

    # Emit CloudWatch custom metrics
    _emit_metrics(truck_id, fleet_id, input_tokens, output_tokens, model_id)


def _emit_metrics(truck_id: str, fleet_id: str, input_tokens: int, output_tokens: int, model_id: str):
    """
    Emits token consumption metrics to CloudWatch.
    Dimensions allow filtering by fleet or model in dashboards and alarms.
    """
    cloudwatch.put_metric_data(
        Namespace=NAMESPACE,
        MetricData=[
            {
                "MetricName": "InputTokens",
                "Dimensions": [
                    {"Name": "Fleet", "Value": fleet_id},
                    {"Name": "Model", "Value": model_id},
                ],
                "Value": input_tokens,
                "Unit": "Count",
            },
            {
                "MetricName": "OutputTokens",
                "Dimensions": [
                    {"Name": "Fleet", "Value": fleet_id},
                    {"Name": "Model", "Value": model_id},
                ],
                "Value": output_tokens,
                "Unit": "Count",
            },
        ],
    )
