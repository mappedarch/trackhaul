import json
import logging

from agents.orchestrator import build_orchestrator

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Compile once at Lambda init time — not inside the handler.
# Lambda reuses the execution environment across invocations.
# Building the graph inside the handler would recompile on every call.
orchestrator = build_orchestrator()


def handler(event, context):
    """
    Lambda entry point. Triggered by SQS.
    Each SQS message must contain:
      - truck_id: str
      - incident_type: one of fault_code | fuel_anomaly | safety_score
      - plus incident-specific fields (fault_code, deviation_pct, etc.)
    """
    results = []

    for record in event.get("Records", []):
        try:
            body = json.loads(record["body"])
            truck_id = body.get("truck_id", "UNKNOWN")

            logger.info(json.dumps({
                "event":      "incident_received",
                "truck_id":   truck_id,
                "incident_type": body.get("incident_type", "unknown"),
            }))

            result = orchestrator.invoke({
                "truck_id":              truck_id,
                "incident_type":         None,
                "payload":               body,
                "routed_to":             None,
                "worker_result":         None,
                "recommended_action":    None,
                "escalate":              None,
                "guardrail_triggered":   None,   
                "guardrail_reason":      None,  
                "investigation_log":     [],
            })

            logger.info(json.dumps({
                "event":              "incident_processed",
                "truck_id":           truck_id,
                "routed_to":          result["routed_to"],
                "escalate":           result["escalate"],
                "recommended_action": result["recommended_action"],
                # No PII — no driver names, no GPS coordinates
            }))

            results.append({
                "truck_id":           truck_id,
                "routed_to":          result["routed_to"],
                "escalate":           result["escalate"],
                "recommended_action": result["recommended_action"],
            })

        except Exception as e:
            logger.error(json.dumps({
                "event": "incident_processing_error",
                "error": str(e),
                "record": record.get("body", ""),
            }))
            # Re-raise so SQS moves the message to DLQ after max retries
            raise

    return {"processed": len(results), "results": results}