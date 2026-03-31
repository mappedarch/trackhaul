###############################################################################
# TrackHaul — Chaos Simulation Module
#
# PURPOSE: Simulate the "before" state of TrackHaul's AWS environment
#          prior to Control Tower + AFT + LZA governance migration.
#
# IMPORTANT: This module is intentionally misconfigured.
#            Every resource here represents a real anti-pattern found in
#            production accounts during enterprise migrations.
#            DO NOT copy these patterns into real workloads.
#            Run `terraform destroy` before proceeding to Phase 2 enrollment.
#
# TARGET:   Dev account (386324384619) — eu-central-1 only
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # NOTE: Intentionally using LOCAL state for the chaos module.
  # Real chaos: teams don't know where state lives.
  # We'll show this as a finding in the pre-flight audit.
}

provider "aws" {
  region = var.aws_region

  # Cross-account access into Dev using the org access role
  assume_role {
    role_arn = "arn:aws:iam::${var.account_id}:role/OrganizationAccountAccessRole"
  }
}

###############################################################################
# CHAOS FINDING #1 — IAM users with long-lived access keys
#
# Real-world story: Developer joined in 2020, IT created a personal IAM user.
# Key was never rotated. MFA never enforced. Person left the company in 2022.
# Key still active. Classic insider threat / credential leak vector.
###############################################################################

resource "aws_iam_user" "dev_admin" {
  name = "trackhaul-dev-admin"
  path = "/"

  # No tags — impossible to track ownership, cost, or creation date
}

resource "aws_iam_access_key" "dev_admin_key" {
  user = aws_iam_user.dev_admin.name
  # Status defaults to Active — key works immediately with no rotation policy
}

resource "aws_iam_user_policy" "dev_admin_policy" {
  name = "trackhaul-dev-admin-inline-policy"
  user = aws_iam_user.dev_admin.name

  # CHAOS FINDING: Inline policy (not managed), full admin, written in 2019
  # Inline policies bypass SCPs in some edge cases and are invisible in
  # the IAM console's managed policy view.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DevAdminFullAccess"
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
        # No Condition block — no MFA requirement, no IP restriction, no time window
      }
    ]
  })
}

###############################################################################
# CHAOS FINDING #2 — CI/CD service user with AdministratorAccess
#
# Real-world story: Pipeline needed to deploy. Someone attached
# AdministratorAccess managed policy because "it's just CI."
# This account now deploys to prod from dev credentials.
###############################################################################

resource "aws_iam_user" "ci_deploy" {
  name = "trackhaul-ci-deploy"
  path = "/service-accounts/"
  # No tags, no description, no rotation schedule
}

resource "aws_iam_access_key" "ci_deploy_key" {
  user = aws_iam_user.ci_deploy.name
}

resource "aws_iam_user_policy_attachment" "ci_deploy_admin" {
  user       = aws_iam_user.ci_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  # This user can do anything in the account — delete CloudTrail, exfiltrate data,
  # provision crypto-mining infrastructure.
}

###############################################################################
# CHAOS FINDING #3 — Overly permissive S3 bucket (the "temp" bucket)
#
# Real-world story: Created for a one-time data migration in 2021.
# Contains PII (driver IDs, truck GPS data). No encryption. No versioning.
# Public ACL was once enabled — recently removed but access logs were never on,
# so there is no proof of what was accessed.
###############################################################################

/* commenting out
resource "aws_s3_bucket" "temp_data" {
  bucket        = var.chaos_bucket_name
  force_destroy = true # chaos: easy to accidentally delete

  # No tags — no cost allocation, no data classification, no GDPR owner
}

# Versioning deliberately disabled — no recovery from accidental deletes
resource "aws_s3_bucket_versioning" "temp_data" {
  bucket = aws_s3_bucket.temp_data.id
  versioning_configuration {
    status = "Suspended"
  }
}

# No server-side encryption — data at rest is unencrypted
# GDPR Article 32 violation: appropriate technical measures not in place
# resource "aws_s3_bucket_server_side_encryption_configuration" intentionally ABSENT

# Overly permissive bucket policy — any principal in the account can read/write
resource "aws_s3_bucket_policy" "temp_data" {
  bucket = aws_s3_bucket.temp_data.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAllAccountPrincipals"
        Effect    = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action   = "s3:*"
        Resource = [
          "arn:aws:s3:::${var.chaos_bucket_name}",
          "arn:aws:s3:::${var.chaos_bucket_name}/*"
        ]
        # No ssl-only condition, no vpc endpoint restriction
      }
    ]
  })

  depends_on = [aws_s3_bucket.temp_data]
}

*/

###############################################################################
# CHAOS FINDING #4 — Security group with 0.0.0.0/0 on SSH
#
# Real-world story: Engineer needed to SSH into an EC2 instance for debugging.
# Opened port 22 to the world. "Temporary." The instance was terminated in 2022
# but the security group was never cleaned up. It's still attached to nothing —
# but if someone launches a new instance and picks "existing SG" from the list...
###############################################################################

resource "aws_vpc" "chaos" {
  cidr_block           = "10.99.0.0/16"
  enable_dns_hostnames = false # chaos: DNS disabled, service discovery breaks
  enable_dns_support   = true

  # No tags
}

resource "aws_security_group" "wide_open_ssh" {
  name        = "trackhaul-debug-ssh-TEMP"
  description = "TEMP - SSH access for debugging - TODO remove"
  vpc_id      = aws_vpc.chaos.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # The classic finding in every AWS security audit
  }

  ingress {
    description = "RDP from anywhere" # Someone also opened RDP
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # No tags
}

###############################################################################
# CHAOS FINDING #5 — No CloudTrail in the Dev account
#
# CloudTrail is deliberately absent from this module.
# Real-world story: "We'll add it when we productionise this."
# Result: Zero audit trail. No way to know who created the IAM user,
# who last accessed the S3 bucket, or who changed the security group.
# GDPR Article 30 violation: no records of processing activity.
#
# The absence is the finding. Auditors will note: no CloudTrail resource present.
###############################################################################

###############################################################################
# OUTPUTS — expose key identifiers for the audit report
###############################################################################
