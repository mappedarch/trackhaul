"""
TrackHaul Fleet Query — Data Layer
Mock implementation. In production, replaced by DynamoDB queries.
No PII stored — truck IDs only.
"""

MOCK_FLEET = {
    "TH-1001": {"status": "active", "region": "DE", "fuel_level": 82, "speed_kmh": 87},
    "TH-1002": {"status": "fault",  "region": "PL", "fuel_level": 45, "speed_kmh": 0},
    "TH-1003": {"status": "active", "region": "NL", "fuel_level": 61, "speed_kmh": 104},
    "TH-1004": {"status": "idle",   "region": "DE", "fuel_level": 90, "speed_kmh": 0},
    "TH-1005": {"status": "fault",  "region": "PL", "fuel_level": 23, "speed_kmh": 0},
}

def get_vehicle(truck_id: str) -> dict:
    """Fetch a single vehicle record."""
    if truck_id not in MOCK_FLEET:
        return None
    return {"truck_id": truck_id, **MOCK_FLEET[truck_id]}

def filter_by_status(status: str) -> list:
    """Return all vehicles matching a given status."""
    return [
        {"truck_id": tid, **data}
        for tid, data in MOCK_FLEET.items()
        if data["status"] == status
    ]

def filter_by_region(region: str) -> list:
    """Return all vehicles in a given region."""
    return [
        {"truck_id": tid, **data}
        for tid, data in MOCK_FLEET.items()
        if data["region"] == region.upper()
    ]