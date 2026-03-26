# modules/guardduty/main.tf
# GuardDuty — threat detection across all TrackHaul accounts
# Security account is delegated administrator
# Members auto-enrolled via Organizations

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.0"
      configuration_aliases = [aws.security]
    }
  }
}

# -------------------------------------------------------
# GUARDDUTY DETECTOR — MANAGEMENT ACCOUNT
# Created first before delegating administration
# -------------------------------------------------------
resource "aws_guardduty_detector" "management" {
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  tags = {
    Purpose = "Threat-Detection"
    GDPR    = "true"
  }
}

# -------------------------------------------------------
# DELEGATE ADMINISTRATION TO SECURITY ACCOUNT
# Must happen after detector is created
# -------------------------------------------------------
resource "aws_guardduty_organization_admin_account" "this" {
  admin_account_id = var.security_account_id

  depends_on = [aws_guardduty_detector.management]
}

# Look up the detector ID in the Security account
# This detector is auto-created when delegation happens
data "aws_guardduty_detector" "security" {
  provider = aws.security

  depends_on = [aws_guardduty_organization_admin_account.this]
}

# -------------------------------------------------------
# ORGANIZATION CONFIGURATION
# Auto-enables GuardDuty in all current and future accounts
# Must happen after delegated admin is set up
# -------------------------------------------------------
# Organization configuration must run from Security account
resource "aws_guardduty_organization_configuration" "this" {
  auto_enable_organization_members = "ALL"
  detector_id                      = data.aws_guardduty_detector.security.id

  datasources {
    s3_logs {
      auto_enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          auto_enable = true
        }
      }
    }
  }

  provider   = aws.security
  depends_on = [aws_guardduty_organization_admin_account.this]
}