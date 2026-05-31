from langgraph.graph import StateGraph, END
from state.incident_state import IncidentState, Severity


def analyse_safety(state: IncidentState) -> IncidentState:
    """
    Node 1: Classify safety score decline.
    Payload expects: { "current_score": float, "previous_score": float }
    Score range: 0-100. Lower is worse.
    """
    current  = state["payload"].get("current_score", 100.0)
    previous = state["payload"].get("previous_score", 100.0)
    decline  = previous - current  # positive number means score dropped

    if current < 40:
        severity = Severity.CRITICAL
        description = f"Safety score critically low at {current} (declined {decline:.1f} points)"
    elif decline >= 20:
        severity = Severity.HIGH
        description = f"Safety score dropped {decline:.1f} points to {current} — rapid decline"
    elif decline >= 10:
        severity = Severity.MEDIUM
        description = f"Safety score declined {decline:.1f} points to {current} — review required"
    else:
        severity = Severity.LOW
        description = f"Safety score stable at {current} (minor change of {decline:.1f} points)"

    log = state.get("investigation_log", [])
    log.append(f"Safety analysis: {description}")

    return {
        **state,
        "fault_description": description,
        "severity": severity,
        "investigation_log": log,
    }


def decide_safety_action(state: IncidentState) -> IncidentState:
    """
    Node 2: Recommend action based on safety severity.
    """
    severity = state["severity"]

    actions = {
        Severity.CRITICAL: "Suspend driver pending mandatory safety review — notify fleet manager",
        Severity.HIGH:     "Schedule driver coaching session within 48 hours",
        Severity.MEDIUM:   "Flag for dispatcher awareness — review driving events",
        Severity.LOW:      "No action required — log for monthly trend report",
    }

    action = actions[severity]
    escalate = severity in (Severity.CRITICAL, Severity.HIGH)

    log = state["investigation_log"]
    log.append(f"Safety decision: {'ESCALATE' if escalate else 'MONITOR'} — {action}")

    return {
        **state,
        "recommended_action": action,
        "escalate": escalate,
        "investigation_log": log,
    }


def build_safety_graph():
    graph = StateGraph(IncidentState)

    graph.add_node("analyse", analyse_safety)
    graph.add_node("decide", decide_safety_action)

    graph.set_entry_point("analyse")
    graph.add_edge("analyse", "decide")
    graph.add_edge("decide", END)

    return graph.compile()