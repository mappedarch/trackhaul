from typing import TypedDict, Optional
from enum import Enum


class IncidentType(str, Enum):
    FAULT_CODE    = "fault_code"
    FUEL_ANOMALY  = "fuel_anomaly"
    SAFETY_SCORE  = "safety_score"
    UNKNOWN       = "unknown"


class OrchestratorState(TypedDict):
    # --- Input fields (set by Lambda on entry) ---
    truck_id:      str
    incident_type: Optional[IncidentType]
    payload:       dict

    # --- Populated by orchestrator classify node ---
    routed_to:     Optional[str]

    # --- Populated by worker agents, written back by orchestrator ---
    worker_result: Optional[dict]

    # --- Final output ---
    recommended_action: Optional[str]
    escalate:           Optional[bool]

    # --- Guardrail fields ---
    guardrail_triggered: Optional[bool]
    guardrail_reason:    Optional[str]

    # --- Audit trail ---
    investigation_log: list[str]
