import logging
from langgraph.graph import StateGraph, END
from state.orchestrator_state import OrchestratorState, IncidentType
from state.incident_state import IncidentState, Severity
from agents.incident_responder import build_graph as build_fault_graph
from agents.fuel_agent import build_fuel_graph
from agents.safety_agent import build_safety_graph
from agents.guardrails import validate_input
import os
import json
import boto3

logger = logging.getLogger(__name__)

_fault_agent  = build_fault_graph()
_fuel_agent   = build_fuel_graph()
_safety_agent = build_safety_graph()


def classify_incident(state: OrchestratorState) -> OrchestratorState:
    raw_type = state["payload"].get("incident_type", "unknown")
    try:
        incident_type = IncidentType(raw_type)
    except ValueError:
        incident_type = IncidentType.UNKNOWN
    log = state.get("investigation_log", [])
    log.append(f"Orchestrator: classified incident as {incident_type}")
    return {**state, "incident_type": incident_type, "investigation_log": log}


def route_after_validation(state: OrchestratorState) -> str:
    if state.get("guardrail_triggered") is True or state.get("routed_to") == "guardrail":
        return "blocked"
    return "classify"


def route_to_worker(state: OrchestratorState) -> str:
    routing = {
        IncidentType.FAULT_CODE:   "fault",
        IncidentType.FUEL_ANOMALY: "fuel",
        IncidentType.SAFETY_SCORE: "safety",
        IncidentType.UNKNOWN:      "unknown",
    }
    return routing.get(state["incident_type"], "unknown")


def _build_worker_input(state: OrchestratorState) -> IncidentState:
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
        "investigation_log":  list(state["investigation_log"]),
    }


def _extract_worker_result(worker_output: IncidentState) -> dict:
    return {
        "recommended_action": worker_output.get("recommended_action"),
        "escalate":           worker_output.get("escalate"),
        "severity":           worker_output.get("severity"),
        "investigation_log":  worker_output.get("investigation_log", []),
    }


def invoke_fault_agent(state: OrchestratorState) -> OrchestratorState:
    worker_input  = _build_worker_input(state)
    worker_output = _fault_agent.invoke(worker_input)
    result        = _extract_worker_result(worker_output)
    log = result["investigation_log"]
    log.append("Orchestrator: fault agent completed")
    _audit_log(state, "worker_invoked", {"worker": "fault_agent"})
    return {
        **state,
        "routed_to":          "fault_agent",
        "worker_result":      result,
        "recommended_action": result["recommended_action"],
        "escalate":           result["escalate"],
        "investigation_log":  log,
    }


def invoke_fuel_agent(state: OrchestratorState) -> OrchestratorState:
    worker_input  = _build_worker_input(state)
    worker_output = _fuel_agent.invoke(worker_input)
    result        = _extract_worker_result(worker_output)
    log = result["investigation_log"]
    log.append("Orchestrator: fuel agent completed")
    _audit_log(state, "worker_invoked", {"worker": "fuel_agent"})
    return {
        **state,
        "routed_to":          "fuel_agent",
        "worker_result":      result,
        "recommended_action": result["recommended_action"],
        "escalate":           result["escalate"],
        "investigation_log":  log,
    }


def invoke_safety_agent(state: OrchestratorState) -> OrchestratorState:
    worker_input  = _build_worker_input(state)
    worker_output = _safety_agent.invoke(worker_input)
    result        = _extract_worker_result(worker_output)
    log = result["investigation_log"]
    log.append("Orchestrator: safety agent completed")
    _audit_log(state, "worker_invoked", {"worker": "safety_agent"})
    return {
        **state,
        "routed_to":          "safety_agent",
        "worker_result":      result,
        "recommended_action": result["recommended_action"],
        "escalate":           result["escalate"],
        "investigation_log":  log,
    }


def handle_unknown(state: OrchestratorState) -> OrchestratorState:
    log = state.get("investigation_log", [])
    log.append("Orchestrator: unknown incident type — no worker invoked")
    return {
        **state,
        "routed_to":          "none",
        "recommended_action": "Manual review required — incident type not recognised",
        "escalate":           True,
        "worker_result":      {},
        "investigation_log":  log,
    }


def dispatch_alert(state: OrchestratorState) -> OrchestratorState:
    """
    Alert dispatch node — runs after every worker.
    Only fires for HIGH and CRITICAL severity.
    LOW and MEDIUM are dropped — prevents alert fatigue at 10,000 vehicle scale.
    No PII in alert payload — truck ID only.
    """
    worker_result = state.get("worker_result") or {}
    severity = worker_result.get("severity")
    log = list(state.get("investigation_log", []))

    gated_severities = {Severity.HIGH, Severity.CRITICAL}

    if severity not in gated_severities:
        log.append(f"Alert dispatch: SKIPPED — severity={severity} below threshold")
        return {**state, "investigation_log": log}

    alert = {
        "truck_id":           state["truck_id"],
        "severity":           severity,
        "routed_to":          state.get("routed_to"),
        "recommended_action": state.get("recommended_action"),
    }

    log.append(f"Alert dispatch: FIRED — severity={severity} truck={state['truck_id']}")
    logger.info({"event": "alert_dispatched", "alert": alert})
    _audit_log(state, "alert_evaluated", {"severity": str(severity)})
    
    return {**state, "investigation_log": log}

def escalate_incident(state: OrchestratorState) -> OrchestratorState:
    """
    Escalation node — runs after alert dispatch.
    Only fires when escalate=True.
    Publishes a structured message to the escalation SQS queue.
    No PII — truck ID only.
    """
    log = list(state.get("investigation_log", []))

    if not state.get("escalate"):
        log.append("Escalation: SKIPPED — escalate=False")
        return {**state, "investigation_log": log}

    queue_url = os.environ.get("ESCALATION_QUEUE_URL")

    if not queue_url:
        # Local dev — no queue configured, log and continue
        log.append("Escalation: SKIPPED — ESCALATION_QUEUE_URL not set (local dev)")
        return {**state, "investigation_log": log}

    message = {
        "truck_id":           state["truck_id"],
        "routed_to":          state.get("routed_to"),
        "recommended_action": state.get("recommended_action"),
        "guardrail_triggered": state.get("guardrail_triggered"),
        "guardrail_reason":   state.get("guardrail_reason"),
    }

    try:
        sqs = boto3.client("sqs", region_name="eu-central-1")
        sqs.send_message(
            QueueUrl=queue_url,
            MessageBody=json.dumps(message),
        )
        log.append(f"Escalation: SENT — truck={state['truck_id']} queue={queue_url}")
        logger.info({"event": "escalation_sent", "truck_id": state["truck_id"]})

    except Exception as e:
        # Never crash the graph on escalation failure — log and continue
        log.append(f"Escalation: FAILED — {str(e)}")
        logger.error({"event": "escalation_failed", "error": str(e)})

    return {**state, "investigation_log": log}

def _audit_log(state: OrchestratorState, event: str, detail: dict = {}):
    """
    Emits a structured CloudWatch log for every significant agent action.
    caller_id and session_id are included on every entry — GDPR audit requirement.
    Never raises — audit failure must never crash the agent.
    """
    try:
        logger.info(json.dumps({
            "event":      event,
            "truck_id":   state.get("truck_id"),
            "caller_id":  state.get("caller_id", "UNKNOWN"),
            "caller_role": state.get("caller_role", "UNKNOWN"),
            "session_id": state.get("session_id", "UNKNOWN"),
            "routed_to":  state.get("routed_to"),
            **detail,
        }))
    except Exception as e:
        logger.error(f"Audit log failed: {e}")

def build_orchestrator():
    graph = StateGraph(OrchestratorState)

    graph.add_node("validate",  validate_input)
    graph.add_node("classify",  classify_incident)
    graph.add_node("fault",     invoke_fault_agent)
    graph.add_node("fuel",      invoke_fuel_agent)
    graph.add_node("safety",    invoke_safety_agent)
    graph.add_node("unknown",   handle_unknown)
    graph.add_node("alert",     dispatch_alert)
    graph.add_node("escalate",  escalate_incident)

    graph.set_entry_point("validate")

    graph.add_conditional_edges("validate", route_after_validation, {
        "blocked":  "escalate",   # blocked payloads go straight to escalation
        "classify": "classify",
    })

    graph.add_conditional_edges("classify", route_to_worker, {
        "fault":   "fault",
        "fuel":    "fuel",
        "safety":  "safety",
        "unknown": "unknown",
    })

    graph.add_edge("fault",    "alert")
    graph.add_edge("fuel",     "alert")
    graph.add_edge("safety",   "alert")
    graph.add_edge("unknown",  "alert")
    graph.add_edge("alert",    "escalate")
    graph.add_edge("escalate", END)

    return graph.compile()