"""
Adds one additional stable day to push the drifted bucket into the
correct position for the drift detector to evaluate.
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

# Seed tomorrow noon UTC — one day ahead so the drifted day is penultimate
tomorrow_noon = datetime.datetime.now(datetime.timezone.utc).replace(
    hour=12, minute=0, second=0, microsecond=0
) + datetime.timedelta(days=1)

for query_type, base_value in BASELINES.items():
    cloudwatch.put_metric_data(
        Namespace  = NAMESPACE,
        MetricData = [{
            "MetricName": "ResponseLengthMean",
            "Dimensions": [
                {"Name": "prompt_version", "Value": "active"},
                {"Name": "query_type",     "Value": query_type}
            ],
            "Timestamp": tomorrow_noon,
            "Value":     base_value,   # stable value — drift was yesterday
            "Unit":      "Count"
        }]
    )
    print(f"Seeded tomorrow stable point for {query_type}: {base_value}")

print("\nDone. Invoke drift detector now.")
