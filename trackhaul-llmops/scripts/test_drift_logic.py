"""
Local unit test for drift detection logic.
Tests the statistical calculation directly without CloudWatch.
No AWS calls made — pure Python.
"""

import math

DRIFT_STD_MULTIPLE = 2.0
MIN_DATA_POINTS    = 3

def mean(values):
    return sum(values) / len(values)

def std_dev(values, values_mean):
    variance = sum((v - values_mean) ** 2 for v in values) / len(values)
    return math.sqrt(variance)

def check_drift(datapoints, query_type):
    if len(datapoints) < MIN_DATA_POINTS:
        print(f"  [{query_type}] insufficient_data — {len(datapoints)} points")
        return

    baseline_values = datapoints[:-1]
    today_value     = datapoints[-1]
    b_mean          = mean(baseline_values)
    b_std           = std_dev(baseline_values, b_mean)
    upper           = b_mean + (DRIFT_STD_MULTIPLE * b_std)
    lower           = b_mean - (DRIFT_STD_MULTIPLE * b_std)
    drifted         = today_value > upper or today_value < lower

    print(f"  [{query_type}]")
    print(f"    baseline_mean={b_mean:.1f}  std={b_std:.1f}")
    print(f"    bounds=[{lower:.1f}, {upper:.1f}]")
    print(f"    today={today_value:.1f}  status={'DRIFTED ⚠' if drifted else 'stable ✓'}")

# Simulate 5 stable days then one drifted day
SCENARIOS = {
    "fault_lookup" : [1300, 1300, 1300, 1300, 3900],  # drifted
    "fuel_anomaly" : [900,  900,  900,  900,  2700],  # drifted
    "safety_score" : [850,  850,  850,  860,   855],  # stable
}

print("=== Drift Detection Logic Test ===\n")
for query_type, datapoints in SCENARIOS.items():
    check_drift(datapoints, query_type)
    print()
