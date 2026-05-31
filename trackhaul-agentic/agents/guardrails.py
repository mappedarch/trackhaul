"""
TrackHaul Agent Guardrails
Layer 1: Input validation — runs before any agent node.

Responsibilities:
- Reject payloads missing required fields
- Detect PII patterns in payload values
- Block oversized payloads (prompt stuffing attack vector)
- All failures set escalate=True and short-circuit the graph

GDPR relevance:
- Ensures no driver names, emails, or coordinates enter the agent pipeline
- Provides an auditable rejection reason for every blocked payload
"""

import re
import logging

from state.orchestrator_state import OrchestratorState

logger = logging.getLogger(__name__)

# ── PII detection patterns ────────────────────────────────────────────────────
# Truck IDs are the only identifier allowed — format TH-XXXX
_TRUCK_ID_PATTERN = re.compile(r'^TH-\d{4}$')

# Patterns that indicate PII has leaked into the payload
_PII_PATTERNS = [
    # Email address
    (re.compile(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'), "email address detected"),
    # Phone number — EU formats
    (re.compile(r'(\+?\d[\d\s\-().]{7,}\d)'), "phone number detected"),
    # GPS coordinates — lat/lon decimal format
    (re.compile(r'\b[-+]?([1-8]?\d(\.\d+)?|90(\.0+)?),\s*[-+]?(180(\.0+)?|((1[0-7]\d)|([1-9]?\d))(\.\d+)?)\b'), "GPS coordinates detected"),
    # Driver name pattern — "First Last" with capital letters (heuristic)
    (re.compile(r'\b[A-Z][a-z]+ [A-Z][a-z]+\b'), "possible driver name detected"),
]

# Maximum payload size — guards against prompt stuffing
_MAX_PAYLOAD_BYTES = 4096

# Required fields in every incident payload
_REQUIRED_FIELDS = ["incident_type"]


def validate_input(state: OrchestratorState) -> OrchestratorState:
    """
    Guardrail node — must be the entry point of the orchestrator graph.
    Returns state with guardrail_triggered=True if any check fails.
    Processing continues to the router node which will short-circuit to END.
    """
    log = state.get("investigation_log", [])
    payload = state.get("payload", {})

    # ── Check 1: Required fields ──────────────────────────────────────────────
    for field in _REQUIRED_FIELDS:
        if field not in payload:
            return _block(state, log, f"Missing required field: {field}")

    # ── Check 2: Truck ID format ──────────────────────────────────────────────
    truck_id = state.get("truck_id", "")
    if not _TRUCK_ID_PATTERN.match(truck_id):
        return _block(state, log, f"Invalid truck_id format: {truck_id} — expected TH-XXXX")

    # ── Check 3: Payload size ─────────────────────────────────────────────────
    import json
    payload_size = len(json.dumps(payload).encode("utf-8"))
    if payload_size > _MAX_PAYLOAD_BYTES:
        return _block(state, log, f"Payload exceeds size limit: {payload_size} bytes > {_MAX_PAYLOAD_BYTES}")

    # ── Check 4: PII scan across all string values in payload ─────────────────
    payload_str = json.dumps(payload)
    for pattern, reason in _PII_PATTERNS:
        if pattern.search(payload_str):
            return _block(state, log, f"PII detected in payload — {reason}")

    # ── All checks passed ─────────────────────────────────────────────────────
    log.append("Guardrail: input validation passed")
    logger.info({"event": "guardrail_passed", "truck_id": truck_id})

    return {
        **state,
        "guardrail_triggered": False,
        "guardrail_reason":    None,
        "investigation_log":   log,
    }


def _block(state: OrchestratorState, log: list, reason: str) -> OrchestratorState:
    """
    Marks state as blocked. The router reads guardrail_triggered
    and short-circuits to END without invoking any worker.
    """
    log.append(f"Guardrail: BLOCKED — {reason}")

    logger.warning({
        "event":     "guardrail_blocked",
        "truck_id":  state.get("truck_id", "UNKNOWN"),
        "reason":    reason,
    })

    return {
        **state,
        "guardrail_triggered": True,
        "guardrail_reason":    reason,
        "recommended_action":  "Payload rejected by input guardrail — manual review required",
        "escalate":            True,
        "routed_to":           "guardrail",
        "investigation_log":   log,
    }