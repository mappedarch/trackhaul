from langgraph.graph import StateGraph, END
from state.incident_state import IncidentState, Severity


def analyse_fuel(state: IncidentState) -> IncidentState:
    """
    Node 1: Classify fuel anomaly severity based on deviation percentage.
    Payload expects: { "deviation_pct": float }
    """
    deviation = state["payload"].get("deviation_pct", 0.0)

    if deviation >= 30:
        severity = Severity.CRITICAL
        description = f"Fuel consumption {deviation}% above baseline — possible theft or major leak"
    elif deviation >= 15:
        severity = Severity.HIGH
        description = f"Fuel consumption {deviation}% above baseline — inspect tank and injectors"
    elif deviation >= 5:
        severity = Severity.MEDIUM
        description = f"Fuel consumption {deviation}% above baseline — monitor next 3 trips"
    else:
        severity = Severity.LOW
        description = f"Fuel consumption within acceptable range ({deviation}% deviation)"

    log = state.get("investigation_log", [])
    log.append(f"Fuel analysis: {description}")

    return {
        **state,
        "fault_description": description,
        "severity": severity,
        "investigation_log": log,
    }


def decide_fuel_action(state: IncidentState) -> IncidentState:
    """
    Node 2: Recommend action based on fuel severity.
    """
    severity = state["severity"]

    actions = {
        Severity.CRITICAL: "Ground truck immediately — dispatch fuel theft/leak investigation team",
        Severity.HIGH:     "Schedule workshop inspection within 24 hours",
        Severity.MEDIUM:   "Flag for dispatcher review — monitor next 3 trips",
        Severity.LOW:      "No action required — log for trend analysis",
    }

    action = actions[severity]
    escalate = severity in (Severity.CRITICAL, Severity.HIGH)

    log = state["investigation_log"]
    log.append(f"Fuel decision: {'ESCALATE' if escalate else 'MONITOR'} — {action}")

    return {
        **state,
        "recommended_action": action,
        "escalate": escalate,
        "investigation_log": log,
    }


def build_fuel_graph():
    graph = StateGraph(IncidentState)

    graph.add_node("analyse", analyse_fuel)
    graph.add_node("decide", decide_fuel_action)

    graph.set_entry_point("analyse")
    graph.add_edge("analyse", "decide")
    graph.add_edge("decide", END)

    return graph.compile()