"""
Feedback Capture Lambda
-----------------------
Receives dispatcher feedback (thumbs up/down/flagged) for an LLM interaction
and writes it to the DynamoDB feedback table.

Input event structure:
{
    "interaction_id": "uuid-from-invocation-wrapper",
    "timestamp": "2024-01-15T10:30:00Z",
    "query_type": "fault_lookup | fuel_anomaly | safety_score",
    "truck_id": "TH-4821",
    "prompt_version": "v3",
    "rating": "thumbs_up | thumbs_down | flagged",
    "correction_text": "optional - dispatcher's suggested correct answer"
}
"""

import json
import os
import logging
import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
TABLE_NAME = os.environ["FEEDBACK_TABLE_NAME"]


def lambda_handler(event, context):
    table = dynamodb.Table(TABLE_NAME)

    # Validate required fields are present
    required_fields = ["interaction_id", "timestamp", "query_type",
                       "truck_id", "prompt_version", "rating"]
    missing = [f for f in required_fields if f not in event]
    if missing:
        logger.error(f"Missing required fields: {missing}")
        return {
            "statusCode": 400,
            "body": json.dumps({"error": f"Missing fields: {missing}"})
        }

    # Validate rating value
    valid_ratings = {"thumbs_up", "thumbs_down", "flagged"}
    if event["rating"] not in valid_ratings:
        logger.error(f"Invalid rating value: {event['rating']}")
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "Invalid rating value"})
        }

    # review_status is pending until a human reviewer acts on it
    # eval_candidate is "false" until reviewer approves it for golden dataset
    item = {
        "interaction_id": event["interaction_id"],
        "timestamp":      event["timestamp"],
        "query_type":     event["query_type"],
        "truck_id":       event["truck_id"],
        "prompt_version": event["prompt_version"],
        "rating":         event["rating"],
        "correction_text": event.get("correction_text", ""),
        "review_status":  "pending",
        "eval_candidate": "false"   # stored as string for GSI hash key
    }

    try:
        table.put_item(Item=item)
        logger.info(
            f"Feedback recorded | interaction_id={event['interaction_id']} "
            f"rating={event['rating']} query_type={event['query_type']} "
            f"truck_id={event['truck_id']}"
        )
        return {
            "statusCode": 200,
            "body": json.dumps({"message": "Feedback recorded"})
        }

    except ClientError as e:
        logger.error(f"DynamoDB write failed: {e.response['Error']['Message']}")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": "Failed to record feedback"})
        }
