from typing import TypedDict, Optional
from enum import Enum

class Severity(str, Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"

class IncidentState(TypedDict):
    """
    Central state object that flows through every node in the graph.
    Every field is optional except truck_id and fault_code.
    Nodes populate fields as the investigation progresses.
    """
    # Input fields - set at graph entry
    truck_id: str
    fault_code: str
    payload: dict 

    # Populated by diagnose node
    fault_description: Optional[str]
    severity: Optional[Severity]

    # Populated by maintenance lookup node
    last_service_date: Optional[str]
    open_work_orders: Optional[int]

    # Populated by decision node
    recommended_action: Optional[str]
    escalate: Optional[bool]

    # Appended by every node as investigation progresses
    investigation_log: list[str]
