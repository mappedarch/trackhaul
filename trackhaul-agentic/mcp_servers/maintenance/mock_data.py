"""
TrackHaul Maintenance — Data Layer
Mock implementation. In production, replaced by DynamoDB queries.
"""

MOCK_MAINTENANCE = {
    "TH-1001": [
        {"date": "2025-05-10", "type": "oil_change",     "status": "completed"},
        {"date": "2025-04-01", "type": "brake_inspect",  "status": "completed"},
    ],
    "TH-1002": [
        {"date": "2025-05-20", "type": "engine_fault",   "status": "open"},
        {"date": "2025-03-15", "type": "oil_change",     "status": "completed"},
    ],
    "TH-1003": [
        {"date": "2025-05-25", "type": "tyre_rotation",  "status": "completed"},
    ],
    "TH-1004": [
        {"date": "2025-05-01", "type": "full_service",   "status": "completed"},
    ],
    "TH-1005": [
        {"date": "2025-05-22", "type": "engine_fault",   "status": "open"},
        {"date": "2025-05-18", "type": "fuel_sensor",    "status": "open"},
    ],
}

def get_maintenance_history(truck_id: str) -> list:
    """Return full maintenance history for a truck."""
    return MOCK_MAINTENANCE.get(truck_id, [])

def get_open_faults(truck_id: str) -> list:
    """Return only open maintenance items for a truck."""
    history = MOCK_MAINTENANCE.get(truck_id, [])
    return [r for r in history if r["status"] == "open"]