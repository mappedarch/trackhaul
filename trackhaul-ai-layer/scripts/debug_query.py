"""
debug_query.py — prints raw DynamoDB results for inspection
"""
import sys
sys.path.insert(0, "lambda_src/fleet_query")
import handler
import json
from decimal import Decimal

def decimal_to_float(obj):
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError

# Query 1 — PL region
print("=== PL region records ===")
results = handler.query_dynamodb_events(region="PL")
print(json.dumps(results, indent=2, default=decimal_to_float))

print("\n=== TH-1023 all records ===")
results = handler.query_dynamodb_events(truck_id="TH-1023")
print(json.dumps(results, indent=2, default=decimal_to_float))
