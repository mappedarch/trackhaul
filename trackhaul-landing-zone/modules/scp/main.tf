# modules/scp/main.tf
# Consolidated SCPs for TrackHaul
# AWS limit is 5 SCPs per target (OU)
# We use 2 consolidated SCPs to stay well within limits
# leaving room for future additions

# -------------------------------------------------------
# SCP 1 — GOVERNANCE CONTROLS
# Combines: block leave org, block root usage,
# block CloudTrail disable, block GuardDuty disable,
# block Security Hub disable
# -------------------------------------------------------
resource "aws_organizations_policy" "governance" {
  name        = "trackhaul-governance"
  description = "Governance controls: root, CloudTrail, GuardDuty, SecurityHub, Org"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "BlockLeaveOrg"
        Effect   = "Deny"
        Action   = "organizations:LeaveOrganization"
        Resource = "*"
      },
      {
        Sid      = "BlockRootUsage"
        Effect   = "Deny"
        Action   = "*"
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:PrincipalType" = "Root"
          }
        }
      },
      {
        Sid    = "BlockCloudTrailDisable"
        Effect = "Deny"
        Action = [
          "cloudtrail:DeleteTrail",
          "cloudtrail:StopLogging",
          "cloudtrail:UpdateTrail",
          "cloudtrail:PutEventSelectors"
        ]
        Resource = "*"
      },
      {
        Sid    = "BlockGuardDutyDisable"
        Effect = "Deny"
        Action = [
          "guardduty:DeleteDetector",
          "guardduty:DisassociateFromMasterAccount",
          "guardduty:DisassociateMembers",
          "guardduty:StopMonitoringMembers",
          "guardduty:UpdateDetector"
        ]
        Resource = "*"
      },
      {
        Sid    = "BlockSecurityHubDisable"
        Effect = "Deny"
        Action = [
          "securityhub:DeleteHub",
          "securityhub:DisableSecurityHub",
          "securityhub:DisassociateFromMasterAccount",
          "securityhub:DisassociateMembers"
        ]
        Resource = "*"
      }
    ]
  })
}

# -------------------------------------------------------
# SCP 2 — GDPR DATA CONTROLS
# Combines: deny non-EU regions + block unencrypted S3
# These are the core GDPR data residency and
# encryption controls
# -------------------------------------------------------
resource "aws_organizations_policy" "gdpr_data" {
  name        = "trackhaul-gdpr-data"
  description = "GDPR: EU data residency and encryption controls"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyNonEURegions"
        Effect = "Deny"
        NotAction = [
          "iam:*",
          "organizations:*",
          "route53:*",
          "budgets:*",
          "waf:*",
          "cloudfront:*",
          "sts:*",
          "support:*",
          "trustedadvisor:*",
          "health:*"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = [
              "eu-central-1",
              "eu-west-1"
            ]
          }
        }
      },
      {
        Sid    = "RequireS3Encryption"
        Effect = "Deny"
        Action = "s3:CreateBucket"
        Resource = "*"
        Condition = {
          "Null" = {
            "s3:x-amz-server-side-encryption" = "true"
          }
          StringNotLike = {
          "aws:PrincipalARN" = [
            "arn:aws:iam::*:role/AWSControlTowerExecution",
            "arn:aws:iam::*:role/aws-controltower-*",
            "arn:aws:iam::*:role/aws-controltower-ConfigRecorderRole*"
          ]
        }
        }
      }
    ]
  })
}

# -------------------------------------------------------
# ATTACH SCPs TO OUs
# 2 SCPs x 3 OUs = 6 attachments
# Well within the 5 SCP per target limit
# We also leave 3 slots free per OU for future SCPs
# -------------------------------------------------------
locals {
  target_ou_ids = [
    var.security_ou_id,
    var.infrastructure_ou_id,
    var.workloads_ou_id
  ]

  scps = {
    governance = aws_organizations_policy.governance.id
    gdpr_data  = aws_organizations_policy.gdpr_data.id
  }
}

resource "aws_organizations_policy_attachment" "scp_attachments" {
  for_each = {
    for pair in setproduct(keys(local.scps), local.target_ou_ids) :
    "${pair[0]}-${pair[1]}" => {
      policy_id = local.scps[pair[0]]
      target_id = pair[1]
    }
  }

  policy_id = each.value.policy_id
  target_id = each.value.target_id
}