"""
test_local_query.py
Invokes fleet_intelligence_handler.py locally to test hybrid RAG without deploying to Lambda.
"""
import sys
sys.path.insert(0, "lambda_src")
import fleet_intelligence_handler as handler

test_cases = [
    {
        "query": "Which trucks had fuel anomalies in Poland this week?",
        "filters": {"region": "PL", "record_types": ["FUEL"]}
    },
    {
        "query": "What is the current status of truck TH-1023 and what fault codes has it raised?",
        "filters": {"truck_id": "TH-1023", "record_types": ["VEHICLE", "EVENT"]}
    },
    {
        "query": "Show me trucks with declining safety scores this month",
        "filters": {"record_types": ["SAFETY"]}
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
