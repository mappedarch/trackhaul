"""
TrackHaul LLMOps — Drift Detector
-----------------------------------
Runs daily via EventBridge Scheduler.

For each query type (fault_lookup, fuel_anomaly, safety_score):
  1. Fetch last 14 days of ResponseLengthMean from CloudWatch
  2. Compute baseline mean and standard deviation
  3. Compare today's value against baseline (2 standard deviation rule)
  4. Emit DriftDetected metric — 1 if drifted, 0 if stable
  5. Publish SNS alert if drift confirmed

Drift threshold: 2 standard deviations from 14-day rolling baseline.
Per strategy doc Section 4 — a single-day exceedance is noise.
Three consecutive days triggers escalation (tracked via SSM counter).

Environment variables:
  METRICS_NAMESPACE  — CloudWatch namespace to read from
  SNS_TOPIC_ARN      — SNS topic for drift alerts
  ENVIRONMENT        — dev | prod
  PROMPT_VERSION     — active prompt version label
"""

import json
import os
import math
import datetime
import boto3
import logging

# ── Logger ────────────────────────────────────────────────────────────────────

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ── Configuration ─────────────────────────────────────────────────────────────

METRICS_NAMESPACE = os.environ.get("METRICS_NAMESPACE", "TrackHaul/LLMOps")
SNS_TOPIC_ARN     = os.environ.get("SNS_TOPIC_ARN", "")
ENVIRONMENT       = os.environ.get("ENVIRONMENT", "dev")
PROMPT_VERSION    = os.environ.get("PROMPT_VERSION", "active")
REGION            = "eu-central-1"

# Drift detection parameters — per strategy doc Section 4
BASELINE_DAYS      = 14     # rolling window for baseline computation
DRIFT_STD_MULTIPLE = 2.0    # flag if value exceeds mean ± 2 std deviations
MIN_DATA_POINTS    = 3      # minimum points required to compute a valid baseline

QUERY_TYPES = ["fault_lookup", "fuel_anomaly", "safety_score"]

# ── AWS clients ───────────────────────────────────────────────────────────────

cloudwatch = boto3.client("cloudwatch", region_name=REGION)
sns        = boto3.client("sns",        region_name=REGION)
ssm        = boto3.client("ssm",        region_name=REGION)

# ── Statistics helpers ────────────────────────────────────────────────────────

def mean(values: list) -> float:
    """Arithmetic mean of a list of floats."""
    return sum(values) / len(values)


def std_dev(values: list, values_mean: float) -> float:
    """
    Population standard deviation.
    Population (not sample) is used here because we are describing the full
    14-day baseline window, not inferring from a sample.
    """
    variance = sum((v - values_mean) ** 2 for v in values) / len(values)
    return math.sqrt(variance)


# ── CloudWatch helpers ────────────────────────────────────────────────────────

def fetch_metric_datapoints(query_type: str, days: int) -> list:
    """
    Fetch ResponseLengthMean datapoints for the given query_type
    over the last N days.

    Returns a list of float values — one per datapoint.
    CloudWatch AVERAGE statistic is used because the wrapper emits
    individual values; CloudWatch aggregates them per period.
    """
    end_time   = datetime.datetime.now(datetime.timezone.utc)
    start_time = end_time - datetime.timedelta(days=days)

    response = cloudwatch.get_metric_statistics(
        Namespace  = METRICS_NAMESPACE,
        MetricName = "ResponseLengthMean",
        Dimensions = [
            {"Name": "prompt_version", "Value": PROMPT_VERSION},
            {"Name": "query_type",     "Value": query_type}
        ],
        StartTime   = start_time,
        EndTime     = end_time,
        Period      = 86400,    # 1-day buckets — daily aggregation
        Statistics  = ["Average"]
    )

    # Sort by timestamp ascending so latest is last
    datapoints = sorted(response["Datapoints"], key=lambda d: d["Timestamp"])
    return [d["Average"] for d in datapoints]


def emit_drift_metric(query_type: str, drifted: bool, today_value: float,
                      baseline_mean: float, baseline_std: float) -> None:
    """
    Emit DriftDetected metric to CloudWatch.
    Value 1 = drift detected, 0 = stable.
    Dimensions allow filtering by query_type and prompt_version in dashboards.
    """
    cloudwatch.put_metric_data(
        Namespace  = METRICS_NAMESPACE,
        MetricData = [
            {
                "MetricName": "DriftDetected",
                "Dimensions": [
                    {"Name": "query_type",     "Value": query_type},
                    {"Name": "prompt_version", "Value": PROMPT_VERSION},
                    {"Name": "environment",    "Value": ENVIRONMENT}
                ],
                "Value": 1.0 if drifted else 0.0,
                "Unit":  "Count"
            },
            {
                # Emit today's value alongside drift flag for dashboard trending
                "MetricName": "ResponseLengthToday",
                "Dimensions": [
                    {"Name": "query_type",     "Value": query_type},
                    {"Name": "prompt_version", "Value": PROMPT_VERSION}
                ],
                "Value": today_value,
                "Unit":  "Count"
            },
            {
                # Emit baseline mean for dashboard comparison
                "MetricName": "ResponseLengthBaseline",
                "Dimensions": [
                    {"Name": "query_type",     "Value": query_type},
                    {"Name": "prompt_version", "Value": PROMPT_VERSION}
                ],
                "Value": baseline_mean,
                "Unit":  "Count"
            }
        ]
    )


# ── SSM consecutive drift counter ─────────────────────────────────────────────
# Strategy doc Section 4: a single-day exceedance is noise.
# Three consecutive days of drift triggers SNS escalation.
# The counter is stored in SSM so it persists across daily Lambda invocations.

def get_consecutive_drift_count(query_type: str) -> int:
    """Read consecutive drift day counter from SSM. Returns 0 if not set."""
    param_name = f"/trackhaul/llmops/drift-counter/{query_type}"
    try:
        response = ssm.get_parameter(Name=param_name)
        return int(response["Parameter"]["Value"])
    except ssm.exceptions.ParameterNotFound:
        return 0


def set_consecutive_drift_count(query_type: str, count: int) -> None:
    """Write consecutive drift day counter to SSM."""
    param_name = f"/trackhaul/llmops/drift-counter/{query_type}"
    ssm.put_parameter(
        Name      = param_name,
        Value     = str(count),
        Type      = "String",
        Overwrite = True
    )


# ── SNS alert ─────────────────────────────────────────────────────────────────

def publish_drift_alert(query_type: str, today_value: float,
                        baseline_mean: float, baseline_std: float,
                        consecutive_days: int) -> None:
    """
    Publish drift alert to SNS.
    Only called after 3 consecutive days of drift — per strategy doc Section 4.
    Single-day exceedances are logged but not alerted.
    """
    if not SNS_TOPIC_ARN:
        logger.warning(json.dumps({"warning": "SNS_TOPIC_ARN not set — alert suppressed"}))
        return

    upper_bound = baseline_mean + (DRIFT_STD_MULTIPLE * baseline_std)
    lower_bound = baseline_mean - (DRIFT_STD_MULTIPLE * baseline_std)

    message = {
        "alert_type"       : "ResponseLengthDrift",
        "environment"      : ENVIRONMENT,
        "query_type"       : query_type,
        "prompt_version"   : PROMPT_VERSION,
        "consecutive_days" : consecutive_days,
        "today_value"      : round(today_value, 1),
        "baseline_mean"    : round(baseline_mean, 1),
        "baseline_std"     : round(baseline_std, 1),
        "upper_bound"      : round(upper_bound, 1),
        "lower_bound"      : round(lower_bound, 1),
        "action"           : "Review prompt version and recent model behaviour. Initiate prompt review per runbook docs/runbooks/drift-detected.md"
    }

    sns.publish(
        TopicArn = SNS_TOPIC_ARN,
        Subject  = f"[TrackHaul LLMOps] Response drift detected — {query_type} ({ENVIRONMENT})",
        Message  = json.dumps(message, indent=2)
    )

    logger.info(json.dumps({"event": "drift_alert_published", "query_type": query_type}))


# ── Core drift check ──────────────────────────────────────────────────────────

def check_drift_for_query_type(query_type: str) -> dict:
    """
    Run drift check for a single query type.
    Returns a result dict summarising the outcome.
    """
    logger.info(json.dumps({"event": "drift_check_start", "query_type": query_type}))

    # Fetch 14-day window
    datapoints = fetch_metric_datapoints(query_type, days=BASELINE_DAYS)

    if len(datapoints) < MIN_DATA_POINTS:
        # Not enough data to compute a meaningful baseline
        # This is expected in the first days after deployment
        logger.warning(json.dumps({
            "event"      : "insufficient_data",
            "query_type" : query_type,
            "points"     : len(datapoints),
            "required"   : MIN_DATA_POINTS
        }))
        return {
            "query_type" : query_type,
            "status"     : "insufficient_data",
            "points"     : len(datapoints)
        }

    # Use all but the last point as baseline, last point as today
    # In production with 14 days of data the last bucket is today
    baseline_values = datapoints[:-1]
    today_value     = datapoints[-1]

    baseline_mean = mean(baseline_values)
    baseline_std  = std_dev(baseline_values, baseline_mean)

    upper_bound = baseline_mean + (DRIFT_STD_MULTIPLE * baseline_std)
    lower_bound = baseline_mean - (DRIFT_STD_MULTIPLE * baseline_std)

    drifted = today_value > upper_bound or today_value < lower_bound

    # Emit metric regardless of drift status — 0 or 1
    emit_drift_metric(query_type, drifted, today_value, baseline_mean, baseline_std)

    # Update consecutive drift counter in SSM
    consecutive = get_consecutive_drift_count(query_type)
    if drifted:
        consecutive += 1
        set_consecutive_drift_count(query_type, consecutive)
    else:
        # Reset counter on stable day
        if consecutive > 0:
            set_consecutive_drift_count(query_type, 0)
        consecutive = 0

    # Escalate only after 3 consecutive days — single-day exceedance is noise
    if drifted and consecutive >= 3:
        publish_drift_alert(query_type, today_value, baseline_mean,
                            baseline_std, consecutive)

    result = {
        "query_type"       : query_type,
        "status"           : "drifted" if drifted else "stable",
        "today_value"      : round(today_value, 1),
        "baseline_mean"    : round(baseline_mean, 1),
        "baseline_std"     : round(baseline_std, 1),
        "upper_bound"      : round(upper_bound, 1),
        "lower_bound"      : round(lower_bound, 1),
        "consecutive_days" : consecutive,
        "alert_sent"       : drifted and consecutive >= 3
    }

    logger.info(json.dumps({"event": "drift_check_complete", **result}))
    return result


# ── Handler ───────────────────────────────────────────────────────────────────

def handler(event, context):
    """
    Lambda handler — invoked daily by EventBridge Scheduler.
    Runs drift check for all three query types.
    """
    logger.info(json.dumps({"event": "drift_detector_start", "environment": ENVIRONMENT}))

    results = []
    for query_type in QUERY_TYPES:
        result = check_drift_for_query_type(query_type)
        results.append(result)

    # Summary log — one line per run for easy CloudWatch Insights querying
    summary = {
        "event"       : "drift_detector_complete",
        "environment" : ENVIRONMENT,
        "results"     : results,
        "drifted"     : [r["query_type"] for r in results if r.get("status") == "drifted"],
        "stable"      : [r["query_type"] for r in results if r.get("status") == "stable"]
    }
    logger.info(json.dumps(summary))

    return {
        "statusCode": 200,
        "body"      : json.dumps(summary)
    }