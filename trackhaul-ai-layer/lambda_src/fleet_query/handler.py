"""
handler.py — Fleet Intelligence Assistant Lambda Orchestrator
Hybrid RAG: DynamoDB (live events) + Bedrock Knowledge Base (static docs)
No PII enters the LLM — truck IDs only.

Query strategy:
- By truck_id: query TruckRecordTypeIndex GSI per record type
- By region: query RegionIndex GSI for truck IDs, then TruckRecordTypeIndex per truck
- Never uses scan()
"""

import json
import boto3
import os
from decimal import Decimal
from boto3.dynamodb.conditions import Key

# ── Config ───────────────────────────────────────────────────────────────────
REGION         = os.environ.get("AWS_REGION", "eu-central-1")
TABLE_NAME     = os.environ.get("DYNAMODB_TABLE", "trackhaul-vehicles-dev")
KB_ID          = os.environ.get("KNOWLEDGE_BASE_ID", "G8TARXJU9J")
MODEL_ID       = os.environ.get("MODEL_ID", "eu.anthropic.claude-sonnet-4-5-20250929-v1:0")
MAX_KB_RESULTS = int(os.environ.get("MAX_KB_RESULTS", "3"))
MAX_TRUCKS     = int(os.environ.get("MAX_TRUCKS", "20"))

# All record types stored in the table
RECORD_TYPES = ["VEHICLE", "EVENT", "FUEL", "SAFETY"]

# ── Clients ──────────────────────────────────────────────────────────────────
dynamodb        = boto3.resource("dynamodb", region_name=REGION)
table           = dynamodb.Table(TABLE_NAME)
bedrock_agent   = boto3.client("bedrock-agent-runtime", region_name=REGION)
bedrock_runtime = boto3.client("bedrock-runtime", region_name=REGION)


# ── Helpers ──────────────────────────────────────────────────────────────────
def decimal_to_float(obj):
    """Convert Decimal to float for JSON serialisation."""
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError


def query_truck_record_type(truck_id: str, record_type: str) -> list:
    """
    Query TruckRecordTypeIndex GSI for a specific truck and record type.
    e.g. all FUEL records for TH-1023.
    """
    response = table.query(
        IndexName="TruckRecordTypeIndex",
        KeyConditionExpression=Key("truck_id").eq(truck_id) & Key("record_type").eq(record_type)
    )
    return response.get("Items", [])


def query_by_truck_id(truck_id: str, record_types: list = None) -> list:
    """
    Fetch all record types for a specific truck.
    Queries TruckRecordTypeIndex once per record type.
    """
    types_to_fetch = record_types or RECORD_TYPES
    results = []
    for record_type in types_to_fetch:
        results.extend(query_truck_record_type(truck_id, record_type))
    return results


def get_truck_ids_by_region(region: str) -> list:
    """
    Query RegionIndex GSI to get distinct truck IDs in a region.
    Returns list of truck_id strings.
    """
    response = table.query(
        IndexName="RegionIndex",
        KeyConditionExpression=Key("region").eq(region),
        Limit=MAX_TRUCKS
    )
    items = response.get("Items", [])
    return list({item["truck_id"] for item in items if "truck_id" in item})


def query_by_region(region: str, record_types: list = None) -> list:
    """
    Query by region:
    1. Get truck IDs from RegionIndex GSI
    2. Query TruckRecordTypeIndex per truck per record type
    """
    truck_ids = get_truck_ids_by_region(region)
    results = []
    for truck_id in truck_ids:
        results.extend(query_by_truck_id(truck_id, record_types))
    return results


def query_all(record_types: list = None) -> list:
    """
    No truck_id or region filter.
    Query all regions, deduplicate by PK.
    """
    seen = set()
    results = []
    for region in ["DE", "PL", "NL"]:
        for item in query_by_region(region, record_types):
            if item["PK"] not in seen:
                seen.add(item["PK"])
                results.append(item)
    return results


def fetch_live_events(truck_id: str = None, region: str = None, record_types: list = None) -> list:
    """
    Route to correct query strategy. Never uses scan().
    record_types — optional list to restrict e.g. ["FUEL", "EVENT"]
    """
    if truck_id:
        return query_by_truck_id(truck_id, record_types)
    elif region:
        return query_by_region(region, record_types)
    else:
        return query_all(record_types)


# ── Knowledge Base ───────────────────────────────────────────────────────────
def query_knowledge_base(query_text: str) -> str:
    """Retrieve relevant chunks from Bedrock Knowledge Base."""
    response = bedrock_agent.retrieve(
        knowledgeBaseId=KB_ID,
        retrievalQuery={"text": query_text},
        retrievalConfiguration={
            "vectorSearchConfiguration": {"numberOfResults": MAX_KB_RESULTS}
        },
    )
    chunks = response.get("retrievalResults", [])
    if not chunks:
        return "No relevant documentation found."
    return "\n\n".join(r["content"]["text"] for r in chunks)


# ── Prompt ───────────────────────────────────────────────────────────────────
def build_prompt(user_query: str, kb_context: str, live_events: list) -> str:
    """Merge KB and live event context into a single prompt. No PII."""
    live_context = json.dumps(live_events, indent=2, default=decimal_to_float)
    return f"""You are the TrackHaul Fleet Intelligence Assistant.
Answer the dispatcher's question using only the context provided below.
Rules:
- Use truck IDs only — never reference driver names or GPS coordinates
- If the answer is not in the context, say "Insufficient data available"
- Be concise and factual

--- FLEET DOCUMENT CONTEXT ---
{kb_context}

--- LIVE FLEET EVENT DATA ---
{live_context}

--- DISPATCHER QUESTION ---
{user_query}

Answer:"""


# ── Bedrock Invoke ───────────────────────────────────────────────────────────
def invoke_claude(prompt: str) -> str:
    """Call Bedrock Claude with the merged prompt."""
    body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 512,
        "messages": [{"role": "user", "content": prompt}],
    }
    response = bedrock_runtime.invoke_model(
        modelId=MODEL_ID,
        contentType="application/json",
        accept="application/json",
        body=json.dumps(body),
    )
    result = json.loads(response["body"].read())
    return result["content"][0]["text"]


# ── Main handler ─────────────────────────────────────────────────────────────
def lambda_handler(event, context):
    """
    Expected event payload:
    {
        "query": "Which trucks had fuel anomalies in Poland this week?",
        "filters": {
            "truck_id":     "TH-1023",        # optional
            "region":       "PL",             # optional
            "record_types": ["FUEL", "EVENT"] # optional — restrict record types fetched
        }
    }
    """
    user_query   = event.get("query", "")
    filters      = event.get("filters", {})

    if not user_query:
        return {"statusCode": 400, "body": "Missing query field"}

    kb_context  = query_knowledge_base(user_query)
    live_events = fetch_live_events(
        truck_id     = filters.get("truck_id"),
        region       = filters.get("region"),
        record_types = filters.get("record_types"),
    )

    prompt = build_prompt(user_query, kb_context, live_events)
    answer = invoke_claude(prompt)

    return {
        "statusCode":           200,
        "query":                user_query,
        "kb_chunks_retrieved":  MAX_KB_RESULTS,
        "live_events_retrieved": len(live_events),
        "answer":               answer,
    }
