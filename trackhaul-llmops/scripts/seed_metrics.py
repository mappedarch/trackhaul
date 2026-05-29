"""
TrackHaul LLMOps — Metric Seeder
---------------------------------
Invokes the Bedrock wrapper Lambda with realistic queries across all three
query types to seed CloudWatch with ResponseLengthMean data points.

Run this before building the drift detector to ensure there is baseline
data in CloudWatch to read from.

Usage:
    python scripts/seed_metrics.py
"""

import json
import time
import boto3

# ── Configuration ─────────────────────────────────────────────────────────────

REGION        = "eu-central-1"
FUNCTION_NAME = "trackhaul-llm-wrapper-dev"
DELAY_SECONDS = 2   # avoid Bedrock throttling between invocations

# Realistic dispatcher queries — no PII, truck IDs only
INVOCATIONS = [
    {"query": "What does fault code P0300 mean for truck TH-4821?",          "query_type": "fault_lookup",  "truck_id": "TH-4821", "fleet_region": "DE"},
    {"query": "What does fault code P0171 indicate for truck TH-3302?",       "query_type": "fault_lookup",  "truck_id": "TH-3302", "fleet_region": "PL"},
    {"query": "Explain fault code P0420 for truck TH-5510.",                  "query_type": "fault_lookup",  "truck_id": "TH-5510", "fleet_region": "NL"},
    {"query": "Which trucks had fuel anomalies in Poland this week?",          "query_type": "fuel_anomaly",  "truck_id": "TH-1001", "fleet_region": "PL"},
    {"query": "Show fuel consumption anomalies for truck TH-2200 this month.", "query_type": "fuel_anomaly",  "truck_id": "TH-2200", "fleet_region": "DE"},
    {"query": "Are there fuel anomalies for trucks operating in Netherlands?",  "query_type": "fuel_anomaly",  "truck_id": "TH-3310", "fleet_region": "NL"},
    {"query": "Show drivers with declining safety scores this month.",          "query_type": "safety_score",  "truck_id": "TH-4400", "fleet_region": "DE"},
    {"query": "What is the safety score trend for truck TH-5521?",             "query_type": "safety_score",  "truck_id": "TH-5521", "fleet_region": "PL"},
    {"query": "Which trucks in Germany have the lowest safety scores?",        "query_type": "safety_score",  "truck_id": "TH-6600", "fleet_region": "DE"},
]

# ── AWS client ────────────────────────────────────────────────────────────────

lambda_client = boto3.client("lambda", region_name=REGION)

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    print(f"Seeding {len(INVOCATIONS)} invocations into {FUNCTION_NAME}\n")

    for i, payload in enumerate(INVOCATIONS, 1):
        print(f"[{i:02d}/{len(INVOCATIONS)}] query_type={payload['query_type']:15s} truck={payload['truck_id']} ", end="", flush=True)

        try:
            response = lambda_client.invoke(
                FunctionName   = FUNCTION_NAME,
                InvocationType = "RequestResponse",
                Payload        = json.dumps(payload)
            )

            result = json.loads(response["Payload"].read())
            answer_len = len(result.get("answer", ""))
            tokens_in  = result.get("input_tokens", 0)
            tokens_out = result.get("output_tokens", 0)

            print(f"| response_length={answer_len:4d} chars | in={tokens_in:3d} out={tokens_out:3d} tokens ✓")

        except Exception as e:
            print(f"| ERROR: {e}")

        time.sleep(DELAY_SECONDS)

    print(f"\nDone. Check CloudWatch namespace TrackHaul/LLMOps for ResponseLengthMean.")
    print("Allow 2-3 minutes for metrics to appear.")

if __name__ == "__main__":
    main()
