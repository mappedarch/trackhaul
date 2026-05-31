"""
TrackHaul Alert Dispatch — Data Layer
Mock implementation. In production, replaced by SNS publish calls.
"""

# In-memory alert log — simulates what would be written to DynamoDB
ALERT_LOG = []

def dispatch_alert(truck_id: str, severity: str, message: str) -> dict:
    """
    Record an alert for a truck.
    Severity: low, medium, high, critical
    """
    alert = {
        "truck_id": truck_id,
        "severity": severity,
        "message":  message,
        "status":   "dispatched"
    }
    ALERT_LOG.append(alert)
    return alert

def get_alert_log() -> list:
    """Return all alerts dispatched in this session."""
    return ALERT_LOG if ALERT_LOG else [{"message": "No alerts dispatched"}]