from langgraph.graph import StateGraph, END
from state.orchestrator_state import OrchestratorState, IncidentType
from state.incident_state import IncidentState, Severity
from agents.incident_responder import build_graph as build_fault_graph
from agents.fuel_agent import build_fuel_graph
from agents.safety_agent import build_safety_graph


# --- Compile worker graphs once at module load ---
# Compiling inside the node function would rebuild the graph on every
# invocation — expensive at 10,000 vehicle scale.
_fault_agent  = build_fault_graph()
_fuel_agent   = build_fuel_graph()
_safety_agent = build_safety_graph()


def classify_incident(state: OrchestratorState) -> OrchestratorState:
    """
    Node 1: Determine incident type from payload.
    The SQS message must contain an 'incident_type' field.
    If missing or unrecognised, defaults to UNKNOWN.
    """
    raw_type = state["payload"].get("incident_type", "unknown")

    try:
        incident_type = IncidentType(raw_type)
    except ValueError:
        incident_type = IncidentType.UNKNOWN

    log = state.get("investigation_log", [])
    log.append(f"Orchestrator: classified incident as {incident_type}")

    return {
        **state,
        "incident_type": incident_type,
        "investigation_log": log,
    }


def _build_worker_input(state: OrchestratorState) -> IncidentState:
    """
    Bridge OrchestratorState → IncidentState for worker invocation.
    Workers receive truck_id, payload, and a fresh investigation_log
    that continues from the orchestrator log.
    """
    return {
        "truck_id":           state["truck_id"],
        "fault_code":         state["payload"].get("fault_code", "UNKNOWN"),
        "payload":            state["payload"],
        "fault_description":  None,
        "severity":           None,
        "last_service_date":  None,
        "open_work_orders":   None,
        "recommended_action": None,
        "escalate":           None,
        "investigation_log":  list(state["investigation_log"]),  # copy, not reference
    }


def _extract_worker_result(worker_output: IncidentState) -> dict:
    """
    Extract the fields the orchestrator cares about from worker output.
    """
    return {
        "recommended_action": worker_output.get("recommended_action"),
        "escalate":           worker_output.get("escalate"),
        "severity":           worker_output.get("severity"),
        "investigation_log":  worker_output.get("investigation_log", []),
    }


def invoke_fault_agent(state: OrchestratorState) -> OrchestratorState:
    """Node: delegate to fault diagnosis worker."""
    worker_input  = _build_worker_input(state)
    worker_output = _fault_agent.invoke(worker_input)
    result        = _extract_worker_result(worker_output)

    log = result["investigation_log"]
    log.append("Orchestrator: fault agent completed")

    return {
        **state,
        "routed_to":          "fault_agent",
        "worker_result":      result,
        "recommended_action": result["recommended_action"],
        "escalate":           result["escalate"],
        "investigation_log":  log,
    }


def invoke_fuel_agent(state: OrchestratorState) -> OrchestratorState:
    """Node: delegate to fuel anomaly worker."""
    worker_input  = _build_worker_input(state)
    worker_output = _fuel_agent.invoke(worker_input)
    result        = _extract_worker_result(worker_output)

    log = result["investigation_log"]
    log.append("Orchestrator: fuel agent completed")

    return {
        **state,
        "routed_to":          "fuel_agent",
        "worker_result":      result,
        "recommended_action": result["recommended_action"],
        "escalate":           result["escalate"],
        "investigation_log":  log,
    }


def invoke_safety_agent(state: OrchestratorState) -> OrchestratorState:
    """Node: delegate to safety scoring worker."""
    worker_input  = _build_worker_input(state)
    worker_output = _safety_agent.invoke(worker_input)
    result        = _extract_worker_result(worker_output)

    log = result["investigation_log"]
    log.append("Orchestrator: safety agent completed")

    return {
        **state,
        "routed_to":          "safety_agent",
        "worker_result":      result,
        "recommended_action": result["recommended_action"],
        "escalate":           result["escalate"],
        "investigation_log":  log,
    }


def handle_unknown(state: OrchestratorState) -> OrchestratorState:
    """Node: unrecognised incident type — log and return safe default."""
    log = state.get("investigation_log", [])
    log.append(f"Orchestrator: unknown incident type — no worker invoked")

    return {
        **state,
        "routed_to":          "none",
        "recommended_action": "Manual review required — incident type not recognised",
        "escalate":           True,   # unknown = escalate by default
        "investigation_log":  log,
    }


def route_to_worker(state: OrchestratorState) -> str:
    """
    Conditional edge: routes to the correct worker node
    based on classified incident type.
    """
    routing = {
        IncidentType.FAULT_CODE:   "fault",
        IncidentType.FUEL_ANOMALY: "fuel",
        IncidentType.SAFETY_SCORE: "safety",
        IncidentType.UNKNOWN:      "unknown",
    }
    return routing.get(state["incident_type"], "unknown")


def build_orchestrator():
    graph = StateGraph(OrchestratorState)

    # Nodes
    graph.add_node("classify", classify_incident)
    graph.add_node("fault",    invoke_fault_agent)
    graph.add_node("fuel",     invoke_fuel_agent)
    graph.add_node("safety",   invoke_safety_agent)
    graph.add_node("unknown",  handle_unknown)

    # Entry
    graph.set_entry_point("classify")

    # Conditional routing after classify
    graph.add_conditional_edges("classify", route_to_worker, {
        "fault":   "fault",
        "fuel":    "fuel",
        "safety":  "safety",
        "unknown": "unknown",
    })

    # All workers terminate
    graph.add_edge("fault",   END)
    graph.add_edge("fuel",    END)
    graph.add_edge("safety",  END)
    graph.add_edge("unknown", END)

    return graph.compile()


# --- Local test ---
if __name__ == "__main__":
    orchestrator = build_orchestrator()

    tests = [
        {
            "label": "Fault code — HIGH severity",
            "payload": {"incident_type": "fault_code", "fault_code": "P0300"},
        },
        {
            "label": "Fuel anomaly — CRITICAL",
            "payload": {"incident_type": "fuel_anomaly", "deviation_pct": 35.0},
        },
        {
            "label": "Safety score — HIGH decline",
            "payload": {"incident_type": "safety_score", "current_score": 55.0, "previous_score": 80.0},
        },
        {
            "label": "Unknown incident type",
            "payload": {"incident_type": "geofence_breach"},
        },
    ]

    for test in tests:
        print(f"\n=== {test['label']} ===")
        result = orchestrator.invoke({
            "truck_id":           "TH-4821",
            "incident_type":      None,
            "payload":            test["payload"],
            "routed_to":          None,
            "worker_result":      None,
            "recommended_action": None,
            "escalate":           None,
            "investigation_log":  [],
        })
        for entry in result["investigation_log"]:
            print(f"  {entry}")
        print(f"  Routed to:  {result['routed_to']}")
        print(f"  Action:     {result['recommended_action']}")
        print(f"  Escalate:   {result['escalate']}")