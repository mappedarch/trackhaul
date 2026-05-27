"""
test_local_query.py
Invokes handler.py locally to test hybrid RAG without deploying to Lambda.
"""
import sys
sys.path.insert(0, "lambda_src/fleet_query")
import handler

test_cases = [
    {
        # No event_type filter — returns all PL records including FUEL# items
        "query": "Which trucks had fuel anomalies in Poland this week?",
        "filters": {"region": "PL"}
    },
    {
        # truck_id only — returns all record types for TH-1023
        "query": "What is the current status of truck TH-1023 and what fault codes has it raised?",
        "filters": {"truck_id": "TH-1023"}
    },
    {
        # No filters — returns all records, let Claude identify declining scores
        "query": "Show me trucks with declining safety scores this month",
        "filters": {}
    },
]

for tc in test_cases:
    print(f"\n{'='*60}")
    print(f"QUERY: {tc['query']}")
    print(f"{'='*60}")
    result = handler.lambda_handler(tc, None)
    print(f"KB chunks retrieved  : {result['kb_chunks_retrieved']}")
    print(f"Live events retrieved: {result['live_events_retrieved']}")
    print(f"\nANSWER:\n{result['answer']}")
