"""
seed_fleet_data.py
Loads realistic mock fleet event data into trackhaul-vehicles-dev DynamoDB table.
No PII — truck IDs only, no driver names, no GPS coordinates.
record_type attribute added to every item to support TruckRecordTypeIndex GSI.
"""

import boto3
from decimal import Decimal

TABLE_NAME = "trackhaul-vehicles-dev"
REGION     = "eu-central-1"

dynamodb = boto3.resource("dynamodb", region_name=REGION)
table    = dynamodb.Table(TABLE_NAME)

def d(val):
    """Convert float to Decimal for DynamoDB compatibility."""
    return Decimal(str(val))

# ── Vehicle master records ───────────────────────────────────────────────────
vehicles = [
    {"PK": "VEHICLE#TH-4821", "record_type": "VEHICLE", "truck_id": "TH-4821", "make": "Mercedes", "model": "Actros", "year": 2021, "plate": "B-TH-4821",  "region": "DE", "status": "active", "created_at": "2024-01-15T08:00:00Z", "updated_at": "2024-01-15T08:00:00Z"},
    {"PK": "VEHICLE#TH-1023", "record_type": "VEHICLE", "truck_id": "TH-1023", "make": "Volvo",    "model": "FH16",   "year": 2020, "plate": "WA-TH-1023", "region": "PL", "status": "fault",  "created_at": "2024-01-10T07:00:00Z", "updated_at": "2025-05-20T09:15:00Z"},
    {"PK": "VEHICLE#TH-7734", "record_type": "VEHICLE", "truck_id": "TH-7734", "make": "DAF",      "model": "XF",     "year": 2022, "plate": "NL-TH-7734", "region": "NL", "status": "active", "created_at": "2024-02-01T09:00:00Z", "updated_at": "2024-02-01T09:00:00Z"},
    {"PK": "VEHICLE#TH-3345", "record_type": "VEHICLE", "truck_id": "TH-3345", "make": "Scania",   "model": "R500",   "year": 2019, "plate": "B-TH-3345",  "region": "DE", "status": "active", "created_at": "2024-01-20T10:00:00Z", "updated_at": "2024-01-20T10:00:00Z"},
    {"PK": "VEHICLE#TH-5512", "record_type": "VEHICLE", "truck_id": "TH-5512", "make": "MAN",      "model": "TGX",    "year": 2023, "plate": "WA-TH-5512", "region": "PL", "status": "active", "created_at": "2024-03-05T08:30:00Z", "updated_at": "2024-03-05T08:30:00Z"},
]

# ── Fault events ─────────────────────────────────────────────────────────────
fault_events = [
    {"PK": "EVENT#TH-1023#2025-05-20T09:00:00Z", "record_type": "EVENT", "truck_id": "TH-1023", "event_type": "fault",         "fault_code": "P0300", "description": "Random/Multiple Cylinder Misfire Detected",         "severity": "critical", "region": "PL", "resolved": False, "timestamp": "2025-05-20T09:00:00Z"},
    {"PK": "EVENT#TH-4821#2025-05-22T14:30:00Z", "record_type": "EVENT", "truck_id": "TH-4821", "event_type": "fault",         "fault_code": "P0401", "description": "Exhaust Gas Recirculation Flow Insufficient",         "severity": "warning",  "region": "DE", "resolved": True,  "timestamp": "2025-05-22T14:30:00Z"},
    {"PK": "EVENT#TH-7734#2025-05-19T07:45:00Z", "record_type": "EVENT", "truck_id": "TH-7734", "event_type": "geofence",      "fault_code": "NONE",  "description": "Geofence breach — Rotterdam port zone",               "severity": "warning",  "region": "NL", "resolved": True,  "timestamp": "2025-05-19T07:45:00Z"},
    {"PK": "EVENT#TH-3345#2025-05-21T11:00:00Z", "record_type": "EVENT", "truck_id": "TH-3345", "event_type": "fault",         "fault_code": "P0087", "description": "Fuel Rail/System Pressure Too Low",                   "severity": "critical", "region": "DE", "resolved": False, "timestamp": "2025-05-21T11:00:00Z"},
    {"PK": "EVENT#TH-5512#2025-05-23T16:20:00Z", "record_type": "EVENT", "truck_id": "TH-5512", "event_type": "harsh_braking", "fault_code": "NONE",  "description": "Harsh braking event — 3 occurrences in 2 hours",     "severity": "warning",  "region": "PL", "resolved": False, "timestamp": "2025-05-23T16:20:00Z"},
]

# ── Fuel anomalies ───────────────────────────────────────────────────────────
fuel_anomalies = [
    {"PK": "FUEL#TH-1023#2025-05-18T06:00:00Z", "record_type": "FUEL", "truck_id": "TH-1023", "event_type": "fuel_anomaly", "litres_per_100km": d(42.3), "baseline_litres_per_100km": d(31.0), "deviation_pct": d(36.5), "region": "PL", "timestamp": "2025-05-18T06:00:00Z"},
    {"PK": "FUEL#TH-4821#2025-05-17T09:00:00Z", "record_type": "FUEL", "truck_id": "TH-4821", "event_type": "fuel_anomaly", "litres_per_100km": d(35.1), "baseline_litres_per_100km": d(30.5), "deviation_pct": d(15.1), "region": "DE", "timestamp": "2025-05-17T09:00:00Z"},
    {"PK": "FUEL#TH-3345#2025-05-20T12:00:00Z", "record_type": "FUEL", "truck_id": "TH-3345", "event_type": "fuel_anomaly", "litres_per_100km": d(38.9), "baseline_litres_per_100km": d(30.8), "deviation_pct": d(26.3), "region": "DE", "timestamp": "2025-05-20T12:00:00Z"},
]

# ── Safety scores ────────────────────────────────────────────────────────────
safety_scores = [
    {"PK": "SAFETY#TH-1023#2025-05", "record_type": "SAFETY", "truck_id": "TH-1023", "period": "2025-05", "safety_score": 58, "prev_score": 74, "harsh_braking_count": 12, "harsh_acceleration_count": 8,  "speeding_events": 5, "region": "PL"},
    {"PK": "SAFETY#TH-4821#2025-05", "record_type": "SAFETY", "truck_id": "TH-4821", "period": "2025-05", "safety_score": 82, "prev_score": 85, "harsh_braking_count": 3,  "harsh_acceleration_count": 2,  "speeding_events": 1, "region": "DE"},
    {"PK": "SAFETY#TH-7734#2025-05", "record_type": "SAFETY", "truck_id": "TH-7734", "period": "2025-05", "safety_score": 91, "prev_score": 89, "harsh_braking_count": 1,  "harsh_acceleration_count": 0,  "speeding_events": 0, "region": "NL"},
    {"PK": "SAFETY#TH-3345#2025-05", "record_type": "SAFETY", "truck_id": "TH-3345", "period": "2025-05", "safety_score": 63, "prev_score": 71, "harsh_braking_count": 9,  "harsh_acceleration_count": 6,  "speeding_events": 3, "region": "DE"},
    {"PK": "SAFETY#TH-5512#2025-05", "record_type": "SAFETY", "truck_id": "TH-5512", "period": "2025-05", "safety_score": 55, "prev_score": 68, "harsh_braking_count": 15, "harsh_acceleration_count": 11, "speeding_events": 7, "region": "PL"},
]


def write_items(items: list, label: str):
    """Batch write items to DynamoDB."""
    with table.batch_writer() as batch:
        for item in items:
            batch.put_item(Item=item)
    print(f"  ✓ {len(items)} {label} written")


if __name__ == "__main__":
    print(f"Seeding data into {TABLE_NAME} ({REGION})...")
    write_items(vehicles,       "vehicle records")
    write_items(fault_events,   "fault/event records")
    write_items(fuel_anomalies, "fuel anomaly records")
    write_items(safety_scores,  "safety score records")
    print("Done.")
