"""
Feedback Reingestion Lambda
---------------------------
Runs on a schedule (weekly, via EventBridge).
Queries DynamoDB for reviewer-approved corrections (eval_candidate = "true")
and appends them to the golden dataset in S3 as a new versioned JSONL file.

This closes the feedback loop:
  Dispatcher flags bad answer
    -> Reviewer approves correction
      -> This Lambda writes it into the golden dataset
        -> Next eval run picks it up automatically
"""

import json
import os
import logging
import boto3
from datetime import datetime, timezone
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
s3 = boto3.client("s3")

TABLE_NAME   = os.environ["FEEDBACK_TABLE_NAME"]
BUCKET_NAME  = os.environ["GOLDEN_DATASET_BUCKET"]
DATASET_PREFIX = os.environ["GOLDEN_DATASET_PREFIX"]


def lambda_handler(event, context):
    table = dynamodb.Table(TABLE_NAME)

    # -------------------------------------------------------
    # Step 1 — Query all approved corrections from DynamoDB
    # Uses the eval-candidate-index GSI
    # -------------------------------------------------------
    try:
        response = table.query(
            IndexName="eval-candidate-index",
            KeyConditionExpression=boto3.dynamodb.conditions.Key(
                "eval_candidate").eq("true")
        )
        items = response.get("Items", [])
    except ClientError as e:
        logger.error(f"DynamoDB query failed: {e.response['Error']['Message']}")
        raise

    if not items:
        logger.info("No approved corrections found. Nothing to reingest.")
        return {"statusCode": 200, "body": "No new corrections"}

    logger.info(f"Found {len(items)} approved corrections for reingestion")

    # -------------------------------------------------------
    # Step 2 — Format corrections as golden dataset records
    # Each record matches the golden dataset JSONL schema
    # -------------------------------------------------------
    new_records = []
    for item in items:
        record = {
            "query":          item.get("query_text", ""),
            "expected_answer": item.get("correction_text", ""),
            "query_type":     item.get("query_type", ""),
            "truck_id":       item.get("truck_id", ""),
            "source":         "dispatcher_correction",
            "prompt_version": item.get("prompt_version", ""),
            "added_at":       datetime.now(timezone.utc).isoformat()
        }
        new_records.append(record)

    # -------------------------------------------------------
    # Step 3 — Write new versioned JSONL file to S3
    # Version is derived from current date for traceability
    # -------------------------------------------------------
    version_tag = datetime.now(timezone.utc).strftime("%Y%m%d")
    s3_key = f"{DATASET_PREFIX}/corrections/corrections-{version_tag}.jsonl"

    jsonl_content = "\n".join(json.dumps(r) for r in new_records)

    try:
        s3.put_object(
            Bucket=BUCKET_NAME,
            Key=s3_key,
            Body=jsonl_content.encode("utf-8"),
            ContentType="application/json"
        )
        logger.info(f"Written {len(new_records)} corrections to s3://{BUCKET_NAME}/{s3_key}")
    except ClientError as e:
        logger.error(f"S3 write failed: {e.response['Error']['Message']}")
        raise

    # -------------------------------------------------------
    # Step 4 — Mark reingested items in DynamoDB
    # Prevents duplicate reingestion on next run
    # -------------------------------------------------------
    for item in items:
        try:
            table.update_item(
                Key={
                    "interaction_id": item["interaction_id"],
                    "timestamp":      item["timestamp"]
                },
                UpdateExpression="SET eval_candidate = :done",
                ExpressionAttributeValues={":done": "reingested"}
            )
        except ClientError as e:
            # Log but do not fail — partial reingestion is recoverable
            logger.warning(
                f"Failed to mark item {item['interaction_id']} as reingested: "
                f"{e.response['Error']['Message']}"
            )

    return {
        "statusCode": 200,
        "body": json.dumps({
            "reingested_count": len(new_records),
            "s3_key": s3_key
        })
    }
