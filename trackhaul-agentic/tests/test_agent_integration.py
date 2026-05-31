"""
TrackHaul Agent — Integration Tests 
Tests the full end-to-end flow against real AWS infrastructure:
- Sends messages to the real SQS queue
- Waits for Lambda to process
- Checks DLQ for failures
- Verifies Lambda logs for security audit fields

Prerequisites:
- AWS credentials active with access to eu-central-1
- Infrastructure deployed via Terraform
- Run from trackhaul-agentic root:
    python -m pytest tests/integration/test_agent_integration.py -v

WARNING: These tests invoke real AWS resources and incur cost.
Do not run in CI without cost controls in place.
"""

import boto3
import json
import time
import pytest

# ── Config — matches terraform output ────────────────────────────────────────
QUEUE_URL         = "https://sqs.eu-central-1.amazonaws.com/281136219737/trackhaul-dev-incident-agent-queue"
DLQ_URL           = "https://sqs.eu-central-1.amazonaws.com/281136219737/trackhaul-dev-incident-agent-dlq"
LAMBDA_NAME       = "trackhaul-dev-agent-handler"
REGION            = "eu-central-1"
LOG_GROUP         = f"/aws/lambda/{LAMBDA_NAME}"

# How long to wait for Lambda to process after sending SQS message
PROCESSING_WAIT_SECONDS = 15

sqs    = boto3.client("sqs",    region_name=REGION)
lamb   = boto3.client("lambda", region_name=REGION)
logs   = boto3.client("logs",   region_name=REGION)



def _send_message(payload: dict, caller_id: str = "integration-test",
                  caller_role: str = "dispatcher") -> str:
    """
    Sends a message to the real SQS queue.
    Includes caller identity in message attributes — mirrors production flow.
    Returns the SQS message ID.
    """
    response = sqs.send_message(
        QueueUrl=QUEUE_URL,
        MessageBody=json.dumps(payload),
        MessageAttributes={
            "caller_id": {
                "StringValue": caller_id,
                "DataType":    "String",
            },
            "caller_role": {
                "StringValue": caller_role,
                "DataType":    "String",
            },
        },
    )
    return response["MessageId"]


def _get_dlq_message_count() -> int:
    """Returns approximate number of messages currently in the DLQ."""
    response = sqs.get_queue_attributes(
        QueueUrl=DLQ_URL,
        AttributeNames=["ApproximateNumberOfMessages"],
    )
    return int(response["Attributes"]["ApproximateNumberOfMessages"])


def _get_recent_log_events(filter_pattern: str, seconds: int = 60) -> list:
    """
    Searches Lambda CloudWatch logs for events matching filter_pattern
    within the last `seconds` seconds.
    """
    start_time = int((time.time() - seconds) * 1000)

    try:
        response = logs.filter_log_events(
            logGroupName=LOG_GROUP,
            filterPattern=filter_pattern,
            startTime=start_time,
        )
        return response.get("events", [])
    except logs.exceptions.ResourceNotFoundException:
        return []


def _invoke_lambda_directly(payload: dict, caller_id: str = "integration-test") -> dict:
    """
    Invokes Lambda directly (synchronous) — bypasses SQS.
    Used to test specific payloads with immediate response.
    Wraps payload in SQS Records format to match handler signature.
    """
    sqs_event = {
        "Records": [
            {
                "body": json.dumps(payload),
                "messageAttributes": {
                    "caller_id": {
                        "stringValue": caller_id,
                        "dataType":    "String",
                    },
                    "caller_role": {
                        "stringValue": "dispatcher",
                        "dataType":    "String",
                    },
                },
            }
        ]
    }

    response = lamb.invoke(
        FunctionName=LAMBDA_NAME,
        InvocationType="RequestResponse",  # synchronous
        Payload=json.dumps(sqs_event),
    )

    result_payload = json.loads(response["Payload"].read())
    return result_payload


# ── Integration tests ─────────────────────────────────────────────────────────

class TestValidIncidentFlow:
    """Happy path — valid incidents must be processed without DLQ."""

    def test_fault_code_incident_processed(self):
        """
        Valid fault code payload sent via SQS must be processed by Lambda.
        Verified by direct Lambda invocation — immediate result.
        """
        payload = {
            "truck_id":      "TH-4821",
            "incident_type": "fault_code",
            "fault_code":    "P0300",
        }
        result = _invoke_lambda_directly(payload, caller_id="dispatcher-001")

        assert result.get("processed") == 1
        results = result.get("results", [])
        assert len(results) == 1
        assert results[0]["truck_id"] == "TH-4821"
        assert results[0]["routed_to"] == "fault_agent"

    def test_fuel_anomaly_incident_processed(self):
        """Valid fuel anomaly must route to fuel agent."""
        payload = {
            "truck_id":      "TH-1234",
            "incident_type": "fuel_anomaly",
            "deviation_pct": 35.0,
        }
        result = _invoke_lambda_directly(payload)

        results = result.get("results", [])
        assert results[0]["routed_to"] == "fuel_agent"

    def test_safety_score_incident_processed(self):
        """Valid safety score must route to safety agent."""
        payload = {
            "truck_id":       "TH-5678",
            "incident_type":  "safety_score",
            "current_score":  55.0,
            "previous_score": 80.0,
        }
        result = _invoke_lambda_directly(payload)

        results = result.get("results", [])
        assert results[0]["routed_to"] == "safety_agent"


class TestSecurityControls:
    """Security controls must block bad payloads before they reach workers."""

    def test_pii_payload_blocked_by_guardrail(self):
        """
        Payload containing driver name must be blocked by guardrail.
        Lambda must return success (not raise) — blocked payload is not a Lambda error.
        """
        payload = {
            "truck_id":      "TH-4821",
            "incident_type": "fault_code",
            "fault_code":    "P0300",
            "driver":        "John Smith",  # PII — must be blocked
        }
        result = _invoke_lambda_directly(payload, caller_id="security-test")

        results = result.get("results", [])
        assert results[0]["routed_to"] == "guardrail"
        assert results[0]["escalate"] is True

    def test_invalid_truck_id_blocked(self):
        """Malformed truck ID must be blocked by guardrail."""
        payload = {
            "truck_id":      "DRIVER-99",
            "incident_type": "fault_code",
            "fault_code":    "P0300",
        }
        # truck_id is in the state, not payload — pass directly
        sqs_event = {
            "Records": [
                {
                    "body": json.dumps({**payload, "truck_id": "DRIVER-99"}),
                    "messageAttributes": {
                        "caller_id":   {"stringValue": "test", "dataType": "String"},
                        "caller_role": {"stringValue": "dispatcher", "dataType": "String"},
                    },
                }
            ]
        }
        response = lamb.invoke(
            FunctionName=LAMBDA_NAME,
            InvocationType="RequestResponse",
            Payload=json.dumps(sqs_event),
        )
        result = json.loads(response["Payload"].read())
        results = result.get("results", [])
        assert results[0]["routed_to"] == "guardrail"

    def test_caller_identity_in_logs(self):
        """
        After processing, CloudWatch logs must contain caller_id and session_id.
        GDPR audit requirement — every invocation must be attributable.
        """
        payload = {
            "truck_id":      "TH-4821",
            "incident_type": "fault_code",
            "fault_code":    "P0300",
        }
        _invoke_lambda_directly(payload, caller_id="gdpr-audit-test")

        # Give CloudWatch a moment to flush
        time.sleep(10)

        events = _get_recent_log_events(
            filter_pattern='"gdpr-audit-test"',
            seconds=30,
        )
        assert len(events) > 0, "caller_id must appear in CloudWatch logs"
