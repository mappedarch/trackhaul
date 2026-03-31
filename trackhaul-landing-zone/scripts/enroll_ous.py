"""
TrackHaul — Control Tower OU Baseline Enrollment Script

Discovers OUs dynamically from AWS Organizations — no hardcoded IDs.
Applies AWSControlTowerBaseline to each OU except those in EXCLUDED_OUS.
Safe to re-run — already enrolled OUs are detected and skipped.

Usage:
    python enroll_ous.py [--dry-run]

    --dry-run   List OUs that would be enrolled without applying anything

Requirements:
    pip install boto3
    AWS credentials must be set for Management account

Configuration:
    EXCLUDED_OUS     — OU names to skip (Suspended, Management)
    BASELINE_NAME    — CT baseline to apply (AWSControlTowerBaseline)
    BASELINE_VERSION — must match your landing zone version
    REGION           — AWS region where CT is deployed
"""

import boto3
import time
import argparse
from datetime import datetime

# ----------------------------------------------------------------------------
# Configuration — only non-discoverable values are hardcoded
# ----------------------------------------------------------------------------
REGION = "eu-central-1"
BASELINE_NAME = "AWSControlTowerBaseline"
BASELINE_VERSION = "5.0"

# OUs to skip — Suspended accounts and Management OU are never enrolled. CT applied specialized baselines to the Security OU accounts
# individually — CentralSecurityRolesBaseline and CentralConfigBaseline to the Security account, LogArchiveBaseline to Log Archive.
# This is by design — CT treats Security OU accounts differently and doesn't accept AWSControlTowerBaseline at the OU level.
EXCLUDED_OUS = {"Suspended", "suspended", "Management", "Security"}

POLL_INTERVAL_SECONDS = 30
ENROLLMENT_TIMEOUT_SECONDS = 3600


# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
def log(msg):
    timestamp = datetime.now().strftime("%H:%M:%S")
    print(f"[{timestamp}] {msg}")


def get_clients():
    session = boto3.Session(region_name=REGION)
    return (
        session.client("controltower"),
        session.client("organizations"),
        session.client("sts"),
    )


def get_management_account_id(sts_client):
    return sts_client.get_caller_identity()["Account"]


def get_org_id(org_client):
    return org_client.describe_organization()["Organization"]["Id"]


def get_root_id(org_client):
    return org_client.list_roots()["Roots"][0]["Id"]


def get_all_ous(org_client, root_id):
    ous = []
    paginator = org_client.get_paginator("list_organizational_units_for_parent")
    for page in paginator.paginate(ParentId=root_id):
        ous.extend(page["OrganizationalUnits"])
    return ous


def get_baseline_arn(ct_client, baseline_name):
    paginator = ct_client.get_paginator("list_baselines")
    for page in paginator.paginate():
        for baseline in page.get("baselines", []):
            if baseline["name"] == baseline_name:
                return baseline["arn"]
    raise ValueError(f"Baseline '{baseline_name}' not found in region {REGION}")


def check_already_enrolled(ct_client, target_arn):
    try:
        paginator = ct_client.get_paginator("list_enabled_baselines")
        for page in paginator.paginate():
            for baseline in page.get("enabledBaselines", []):
                if baseline.get("targetIdentifier") == target_arn:
                    return True, baseline.get("arn")
        return False, None
    except Exception as e:
        log(f"  Warning: Could not check enrollment status — {e}")
        return False, None


def poll_operation(ct_client, operation_id, ou_name):
    elapsed = 0
    while elapsed < ENROLLMENT_TIMEOUT_SECONDS:
        time.sleep(POLL_INTERVAL_SECONDS)
        elapsed += POLL_INTERVAL_SECONDS
        try:
            response = ct_client.get_baseline_operation(operationIdentifier=operation_id)
            status = response["baselineOperation"]["status"]
            log(f"  [{elapsed // 60}min elapsed] Status: {status}")
            if status == "SUCCEEDED":
                log(f"  SUCCESS: {ou_name} OU enrolled successfully")
                return True
            elif status in ("FAILED", "CANCELLED"):
                log(f"  FAILED: {ou_name} OU enrollment failed")
                log(f"  Check CT console: https://{REGION}.console.aws.amazon.com/controltower/home/organization")
                return False
        except Exception as e:
            log(f"  Error polling operation: {e}")
            return False
    log(f"  TIMEOUT: {ou_name} exceeded {ENROLLMENT_TIMEOUT_SECONDS // 60} minutes")
    return False


def enroll_ou(ct_client, ou, baseline_arn, management_account_id, org_id):
    ou_name = ou["Name"]
    ou_id = ou["Id"]
    target_arn = f"arn:aws:organizations::{management_account_id}:ou/{org_id}/{ou_id}"

    log(f"Processing OU: {ou_name} ({ou_id})")

    already_enrolled, existing_arn = check_already_enrolled(ct_client, target_arn)
    if already_enrolled:
        log(f"  SKIPPED: Already enrolled ({existing_arn})")
        return True

    try:
        response = ct_client.enable_baseline(
            baselineIdentifier=baseline_arn,
            baselineVersion=BASELINE_VERSION,
            targetIdentifier=target_arn,
        )
        operation_id = response.get("operationIdentifier")
        if not operation_id:
            log(f"  ERROR: No operation ID returned")
            return False
        log(f"  Baseline application initiated — operation: {operation_id}")
        log(f"  Polling every {POLL_INTERVAL_SECONDS}s...")
        return poll_operation(ct_client, operation_id, ou_name)

    except ct_client.exceptions.ConflictException as e:
        log(f"  CONFLICT: Already enrolled — {e}")
        return True
    except ct_client.exceptions.ValidationException as e:
        log(f"  VALIDATION ERROR: {e}")
        return False
    except ct_client.exceptions.AccessDeniedException as e:
        log(f"  ACCESS DENIED: Ensure credentials are for Management account ({management_account_id})")
        return False
    except Exception as e:
        log(f"  UNEXPECTED ERROR: {e}")
        return False


# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="Enroll OUs into Control Tower")
    parser.add_argument("--dry-run", action="store_true", help="List OUs without enrolling")
    args = parser.parse_args()

    ct_client, org_client, sts_client = get_clients()

    management_account_id = get_management_account_id(sts_client)
    org_id = get_org_id(org_client)
    root_id = get_root_id(org_client)
    all_ous = get_all_ous(org_client, root_id)
    baseline_arn = get_baseline_arn(ct_client, BASELINE_NAME)

    enrollable_ous = [ou for ou in all_ous if ou["Name"] not in EXCLUDED_OUS]

    log("TrackHaul — Control Tower OU Baseline Enrollment")
    log(f"Management account : {management_account_id}")
    log(f"Org ID             : {org_id}")
    log(f"Baseline           : {BASELINE_NAME} v{BASELINE_VERSION}")
    log(f"OUs discovered     : {len(all_ous)} total, {len(enrollable_ous)} enrollable")
    log(f"Excluded OUs       : {', '.join(EXCLUDED_OUS)}")
    log("-" * 60)

    if args.dry_run:
        log("DRY RUN — no changes will be made")
        log("")
        for ou in all_ous:
            excluded = ou["Name"] in EXCLUDED_OUS
            status = "EXCLUDED" if excluded else "WILL ENROLL"
            log(f"  {status}: {ou['Name']} ({ou['Id']})")
        return

    results = []
    for i, ou in enumerate(enrollable_ous):
        log("")
        success = enroll_ou(ct_client, ou, baseline_arn, management_account_id, org_id)
        results.append({"ou": ou["Name"], "ou_id": ou["Id"], "success": success})

        if not success:
            log("")
            log("STOPPING: Fix the issue then re-run.")
            log("Successfully enrolled OUs will be skipped automatically.")
            break

        if i < len(enrollable_ous) - 1:
            log(f"  Waiting 15s before next OU...")
            time.sleep(15)

    log("")
    log("=" * 60)
    log("ENROLLMENT SUMMARY")
    log("=" * 60)
    for r in results:
        status = "SUCCESS" if r["success"] else "FAILED"
        log(f"  {status}: {r['ou']} OU ({r['ou_id']})")

    failed = [r for r in results if not r["success"]]
    if not failed:
        log("")
        log("All OUs enrolled successfully.")
        log("Next step: Terraform reconciliation — import CT resources into state")
    else:
        log("")
        log(f"{len(failed)} OU(s) failed. Check CT console for CloudFormation stack set errors.")


if __name__ == "__main__":
    main()