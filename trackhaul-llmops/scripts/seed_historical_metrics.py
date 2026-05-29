"""
Seeds 5 days of synthetic ResponseLengthMean data into CloudWatch.
CloudWatch rejects timestamps older than 14 days — 5 days is safe.
Day 1 (yesterday) is injected with a drifted value to test detection.
"""

import boto3
import datetime

REGION    = "eu-central-1"
NAMESPACE = "TrackHaul/LLMOps"

cloudwatch = boto3.client("cloudwatch", region_name=REGION)

BASELINES = {
    "fault_lookup" : 1300,
    "fuel_anomaly" :  900,
    "safety_score" :  850,
}

DRIFT_MULTIPLIER = 3.0

today_noon = datetime.datetime.now(datetime.timezone.utc).replace(
    hour=12, minute=0, second=0, microsecond=0
)

for query_type, base_value in BASELINES.items():
    print(f"Seeding {query_type}...")
    metric_data = []

    for days_ago in range(5, 0, -1):
        timestamp = today_noon - datetime.timedelta(days=days_ago)
        # Day 1 ago is the drifted value — all others are stable baseline
        value = base_value * DRIFT_MULTIPLIER if days_ago == 1 else base_value

        metric_data.append({
            "MetricName": "ResponseLengthMean",
            "Dimensions": [
                {"Name": "prompt_version", "Value": "active"},
                {"Name": "query_type",     "Value": query_type}
            ],
            "Timestamp": timestamp,
            "Value":     value,
            "Unit":      "Count"
        })

    cloudwatch.put_metric_data(Namespace=NAMESPACE, MetricData=metric_data)
    print(f"  Seeded 5 days — baseline={base_value} drift_day={base_value * DRIFT_MULTIPLIER}")

print("\nDone. Wait 2 minutes then invoke the drift detector.")
