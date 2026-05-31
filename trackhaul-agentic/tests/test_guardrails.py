"""
TrackHaul Orchestrator — Guardrail Unit Tests

Tests input validation node in isolation.
No LLM calls — pure graph logic.
Run from trackhaul-agentic root:
    python -m pytest tests/test_guardrails.py -v
"""

import pytest
from agents.orchestrator import build_orchestrator

# Compile once — same pattern as Lambda init
orchestrator = build_orchestrator()


def _invoke(payload: dict, truck_id: str = "TH-4821") -> dict:
    """Helper — builds minimal valid initial state and invokes orchestrator."""
    return orchestrator.invoke({
        "truck_id":            truck_id,
        "incident_type":       None,
        "payload":             payload,
        "routed_to":           None,
        "worker_result":       None,
        "recommended_action":  None,
        "escalate":            None,
        "guardrail_triggered": None,
        "guardrail_reason":    None,
        "investigation_log":   [],
    })


# ── Happy path ────────────────────────────────────────────────────────────────

def test_valid_fault_payload_passes():
    """Clean fault code payload must pass guardrail and reach fault agent."""
    result = _invoke({"incident_type": "fault_code", "fault_code": "P0300"})
    assert result.get("guardrail_triggered") is False
    assert result.get("routed_to") == "fault_agent"


def test_valid_fuel_payload_passes():
    result = _invoke({"incident_type": "fuel_anomaly", "deviation_pct": 35.0})
    assert result.get("guardrail_triggered") is False
    assert result.get("routed_to") == "fuel_agent"


def test_valid_safety_payload_passes():
    result = _invoke({
        "incident_type":  "safety_score",
        "current_score":  55.0,
        "previous_score": 80.0,
    })
    assert result.get("guardrail_triggered") is False
    assert result.get("routed_to") == "safety_agent"


# ── PII detection ─────────────────────────────────────────────────────────────

def test_driver_name_blocked():
    """Payload containing a driver name must be blocked."""
    result = _invoke({
        "incident_type": "fault_code",
        "fault_code":    "P0300",
        "driver":        "John Smith",
    })
    assert result.get("guardrail_triggered") is True
    assert result.get("escalate") is True
    assert result.get("routed_to") == "guardrail"


def test_email_in_payload_blocked():
    result = _invoke({
        "incident_type": "fault_code",
        "fault_code":    "P0300",
        "contact":       "dispatcher@trackhaul.eu",
    })
    assert result.get("guardrail_triggered") is True


def test_gps_coordinates_blocked():
    result = _invoke({
        "incident_type": "fault_code",
        "fault_code":    "P0300",
        "location":      "52.5200, 13.4050",
    })
    assert result.get("guardrail_triggered") is True


# ── Field validation ──────────────────────────────────────────────────────────

def test_missing_incident_type_blocked():
    result = _invoke({"fault_code": "P0300"})
    assert result.get("guardrail_triggered") is True
    assert "incident_type" in result.get("guardrail_reason", "")


def test_missing_truck_id_field_blocked():
    """Malformed truck ID must be blocked."""
    result = _invoke(
        {"incident_type": "fault_code", "fault_code": "P0300"},
        truck_id="DRIVER-99",
    )
    assert result.get("guardrail_triggered") is True
    assert result.get("escalate") is True


# ── Escalation propagation ────────────────────────────────────────────────────

def test_blocked_payload_sets_escalate_true():
    """Any guardrail block must set escalate=True — never silently drop."""
    result = _invoke({
        "incident_type": "fault_code",
        "fault_code":    "P0300",
        "driver":        "John Smith",
    })
    assert result.get("escalate") is True


def test_blocked_payload_has_audit_log_entry():
    """Guardrail blocks must produce an audit log entry."""
    result = _invoke({
        "incident_type": "fault_code",
        "fault_code":    "P0300",
        "driver":        "John Smith",
    })
    blocked_entries = [e for e in result.get("investigation_log", []) if "BLOCKED" in e]
    assert len(blocked_entries) >= 1

# ── Alert dispatch gating ─────────────────────────────────────────────────────

def test_high_severity_fires_alert():
    """HIGH severity fault must fire an alert."""
    result = _invoke({"incident_type": "fault_code", "fault_code": "P0300"})
    fired = [e for e in result.get("investigation_log", []) if "Alert dispatch: FIRED" in e]
    assert len(fired) == 1


def test_low_severity_skips_alert():
    """LOW severity fault must not fire an alert."""
    result = _invoke({"incident_type": "fault_code", "fault_code": "P0420"})
    skipped = [e for e in result.get("investigation_log", []) if "Alert dispatch: SKIPPED" in e]
    assert len(skipped) == 1


def test_unknown_incident_skips_alert():
    """Unknown incident type has no severity — alert must be skipped."""
    result = _invoke({"incident_type": "geofence_breach"})
    skipped = [e for e in result.get("investigation_log", []) if "Alert dispatch: SKIPPED" in e]
    assert len(skipped) == 1


def test_alert_contains_no_pii():
    """Alert log entry must contain truck ID only — no driver names or coordinates."""
    result = _invoke({"incident_type": "fault_code", "fault_code": "P0300"})
    fired = [e for e in result.get("investigation_log", []) if "Alert dispatch: FIRED" in e]
    assert len(fired) == 1
    # Must contain truck ID
    assert "TH-4821" in fired[0]
    # Must not contain anything resembling a name or coordinate
    assert "@" not in fired[0]