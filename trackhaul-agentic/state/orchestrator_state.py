from typing import TypedDict, Optional
from enum import Enum


class IncidentType(str, Enum):
    FAULT_CODE    = "fault_code"
    FUEL_ANOMALY  = "fuel_anomaly"
    SAFETY_SCORE  = "safety_score"
    UNKNOWN       = "unknown"


class OrchestratorState(TypedDict):
    """
    State that flows through the orchestrator graph.
    
    The orchestrator populates incident_type, then delegates to the
    appropriate worker agent. The worker result is written back here
    before the orchestrator produces the final recommendation.
    """
    # --- Input fields (set by Lambda on entry) ---
    truck_id:      str
    incident_type: Optional[IncidentType]
    payload:       dict          # raw incident payload — worker agents read from here

    # --- Populated by orchestrator classify node ---
    routed_to:     Optional[str] # which worker was invoked

    # --- Populated by worker agents, written back by orchestrator ---
    worker_result: Optional[dict]

    # --- Final output ---
    recommended_action: Optional[str]
    escalate:           Optional[bool]

    # --- Audit trail ---
    investigation_log: list[str]