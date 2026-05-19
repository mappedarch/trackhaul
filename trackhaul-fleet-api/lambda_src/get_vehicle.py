import json
import os
import boto3
from boto3.dynamodb.conditions import Key
from decimal import Decimal

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["DYNAMODB_TABLE_NAME"])

# DynamoDB returns numbers as Decimal — convert for JSON serialisation
class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        return super().default(obj)

def handler(event, context):
    print("EVENT:", json.dumps(event))
    truck_id = event.get("pathParameters") or {}
    truck_id = truck_id.get("truckId")

    if not truck_id:
        return {
            "statusCode": 400,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": "truck_id is required"})
        }

    response = table.get_item(
        Key={"PK": f"VEHICLE#{truck_id}"}
    )

    item = response.get("Item")

    if not item:
        return {
            "statusCode": 404,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": f"Vehicle {truck_id} not found"})
        }

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(item, cls=DecimalEncoder)
    }