"""
TrackHaul Agent Lambda Handler

Entry point for SQS-triggered agent invocations.

Security additions (Day 48):
- Caller identity extracted from SQS message attributes
- session_id generated per invocation for end-to-end tracing
- Both propagated through graph state for GDPR audit trail
"""

import json
import logging
import uuid

from agents.orchestrator import build_orchestrator

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Compiled once at Lambda init time — not inside the handler.
# Lambda reuses the execution environment across invocations.
orchestrator = build_orchestrator()


def handler(event, context):
    """
    Lambda entry point. Triggered by SQS.

    Each SQS message must contain in body:
      - truck_id: str
      - incident_type: fault_code | fuel_anomaly | safety_score
      - plus incident-specific fields

    Each SQS message must contain in messageAttributes:
      - caller_id: Cognito user ID of the dispatcher who triggered this
      - caller_role: Cognito group — dispatcher | ops-admin | auditor
    """
    results = []

    for record in event.get("Records", []):
        try:
            body = json.loads(record["body"])
            truck_id = body.get("truck_id", "UNKNOWN")

            # ── Caller identity — GDPR audit requirement ──────────────────────
            # Extracted from SQS message attributes set by API Gateway.
            # Falls back to UNKNOWN — never crashes the handler.
            # session_id is unique per invocation for end-to-end tracing.
            attrs = record.get("messageAttributes", {})
            caller_id   = attrs.get("caller_id",   {}).get("stringValue", "UNKNOWN")
            caller_role = attrs.get("caller_role",  {}).get("stringValue", "UNKNOWN")
            session_id  = str(uuid.uuid4())

            logger.info(json.dumps({
                "event":         "incident_received",
                "truck_id":      truck_id,
                "incident_type": body.get("incident_type", "unknown"),
                "caller_id":     caller_id,
                "caller_role":   caller_role,
                "session_id":    session_id,
            }))

            result = orchestrator.invoke(
                {
                    "truck_id":            truck_id,
                    "incident_type":       None,
                    "payload":             body,
                    "routed_to":           None,
                    "worker_result":       None,
                    "recommended_action":  None,
                    "escalate":            None,
                    "guardrail_triggered": None,
                    "guardrail_reason":    None,
                    "investigation_log":   [],
                    "caller_id":           caller_id,
                    "caller_role":         caller_role,
                    "session_id":          session_id,
                },
                {"recursion_limit": 25},
            )

            logger.info(json.dumps({
                "event":              "incident_processed",
                "truck_id":           truck_id,
                "routed_to":          result["routed_to"],
                "escalate":           result["escalate"],
                "recommended_action": result["recommended_action"],
                "caller_id":          caller_id,
                "session_id":         session_id,
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
                "event":   "incident_processing_error",
                "error":   str(e),
                "record":  record.get("body", ""),
            }))
            # Re-raise so SQS moves message to DLQ after max retries
            raise

    return {"processed": len(results), "results": results}