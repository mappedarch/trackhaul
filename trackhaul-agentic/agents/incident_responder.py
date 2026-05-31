from langgraph.graph import StateGraph, END
from state.incident_state import IncidentState, Severity

def diagnose_fault(state: IncidentState) -> IncidentState:
    """
    Node 1: Diagnose fault code and assign severity.
    """
    fault_lookup = {
        "P0300": ("Random/Multiple Cylinder Misfire", Severity.HIGH),
        "P0171": ("System Too Lean Bank 1", Severity.MEDIUM),
        "P0420": ("Catalyst System Efficiency Below Threshold", Severity.LOW),
        "P0700": ("Transmission Control System Malfunction", Severity.CRITICAL),
    }

    description, severity = fault_lookup.get(
        state["fault_code"],
        ("Unknown fault code", Severity.MEDIUM)
    )

    log = state.get("investigation_log", [])
    log.append(f"Diagnosed {state['fault_code']} as: {description} (severity={severity})")

    return {
        **state,
        "fault_description": description,
        "severity": severity,
        "investigation_log": log,
    }


def lookup_maintenance(state: IncidentState) -> IncidentState:
    """
    Node 2: Check maintenance history for this truck.
    Simulated lookup — Day 42 will replace this with a real DynamoDB call.
    """
    # Simulated maintenance records per truck
    maintenance_db = {
        "TH-4821": {"last_service_date": "2025-03-15", "open_work_orders": 2},
        "TH-1032": {"last_service_date": "2025-01-20", "open_work_orders": 0},
    }

    record = maintenance_db.get(state["truck_id"], {
        "last_service_date": "unknown",
        "open_work_orders": 0
    })

    log = state["investigation_log"]
    log.append(
        f"Maintenance check: last service {record['last_service_date']}, "
        f"open work orders: {record['open_work_orders']}"
    )

    return {
        **state,
        "last_service_date": record["last_service_date"],
        "open_work_orders": record["open_work_orders"],
        "investigation_log": log,
    }


def decide_action(state: IncidentState) -> IncidentState:
    """
    Node 3: Decide whether to escalate or auto-resolve based on
    severity and maintenance history.
    """
    severity = state["severity"]
    open_orders = state.get("open_work_orders", 0)

    # Escalate if critical, or if high severity with existing open work orders
    should_escalate = (
        severity == Severity.CRITICAL or
        (severity == Severity.HIGH and open_orders > 0)
    )

    if should_escalate:
        action = f"Escalate to workshop — {state['fault_description']} requires immediate attention"
    else:
        action = f"Monitor and schedule next available service slot"

    log = state["investigation_log"]
    log.append(f"Decision: {'ESCALATE' if should_escalate else 'MONITOR'} — {action}")

    return {
        **state,
        "recommended_action": action,
        "escalate": should_escalate,
        "investigation_log": log,
    }


def route_by_severity(state: IncidentState) -> str:
    """
    Conditional edge: routes to maintenance lookup only if severity
    warrants it. LOW severity goes straight to decision.
    """
    if state["severity"] == Severity.LOW:
        return "decide"
    return "maintenance"


def build_graph():
    graph = StateGraph(IncidentState)

    # Register nodes
    graph.add_node("diagnose", diagnose_fault)
    graph.add_node("maintenance", lookup_maintenance)
    graph.add_node("decide", decide_action)

    # Entry point
    graph.set_entry_point("diagnose")

    # Conditional edge after diagnose — routes based on severity
    graph.add_conditional_edges("diagnose", route_by_severity, {
        "maintenance": "maintenance",
        "decide": "decide",
    })

    # Fixed edges
    graph.add_edge("maintenance", "decide")
    graph.add_edge("decide", END)

    return graph.compile()


if __name__ == "__main__":
    agent = build_graph()

    # Test 1 — HIGH severity with open work orders, should escalate
    print("=== Test 1: HIGH severity ===")
    result = agent.invoke({
        "truck_id": "TH-4821",
        "fault_code": "P0300",
        "fault_description": None,
        "severity": None,
        "last_service_date": None,
        "open_work_orders": None,
        "recommended_action": None,
        "escalate": None,
        "investigation_log": [],
    })
    for entry in result["investigation_log"]:
        print(f"  {entry}")
    print(f"  Escalate: {result['escalate']}")

    # Test 2 — LOW severity, should skip maintenance lookup
    print("\n=== Test 2: LOW severity ===")
    result = agent.invoke({
        "truck_id": "TH-4821",
        "fault_code": "P0420",
        "fault_description": None,
        "severity": None,
        "last_service_date": None,
        "open_work_orders": None,
        "recommended_action": None,
        "escalate": None,
        "investigation_log": [],
    })
    for entry in result["investigation_log"]:
        print(f"  {entry}")
    print(f"  Escalate: {result['escalate']}")
