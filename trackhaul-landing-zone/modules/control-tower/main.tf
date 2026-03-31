###############################################################################
# TrackHaul — Control Tower Module
#
# Manages the CT landing zone resource.
# CT enabled baselines are managed via scripts/enroll_ous.py — the AWS
# Terraform provider does not yet support aws_controltower_enabled_baseline.
#
# Import command:
#   terraform import module.control_tower.aws_controltower_landing_zone.this \
#     arn:aws:controltower:eu-central-1:258335483092:landingzone/A1848HCOG4VXHEWV
###############################################################################

resource "aws_controltower_landing_zone" "this" {
  version = var.landing_zone_version

  manifest_json = jsonencode({
    governedRegions = ["eu-central-1"]
    backup = {
      enabled = false
    }
    centralizedLogging = {
      accountId = var.log_archive_account_id
      enabled   = true
      configurations = {
        loggingBucket = {
          retentionDays = "365"
        }
        accessLoggingBucket = {
          retentionDays = "3650"
        }
      }
    }
    config = {
      accountId = var.security_account_id
      enabled   = true
      configurations = {
        loggingBucket = {
          retentionDays = "365"
        }
        accessLoggingBucket = {
          retentionDays = "3650"
        }
      }
    }
    securityRoles = {
      accountId = var.security_account_id
      enabled   = true
    }
    accessManagement = {
      enabled = false
    }
  })
}