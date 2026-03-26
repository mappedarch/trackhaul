# modules/config/main.tf
# AWS Config — continuous compliance monitoring
# Rules deployed across all accounts
# Findings aggregated into Security account

# -------------------------------------------------------
# CONFIG RECORDER
# Records configuration changes for all supported resources
# Must be enabled before rules can evaluate anything
# -------------------------------------------------------
resource "aws_config_configuration_recorder" "this" {
  name     = "trackhaul-config-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

# -------------------------------------------------------
# IAM ROLE FOR CONFIG
# Config needs permissions to read your resources
# and write findings to S3
# -------------------------------------------------------
resource "aws_iam_role" "config" {
  name = "trackhaul-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# -------------------------------------------------------
# S3 BUCKET FOR CONFIG
# Config stores configuration snapshots and history here
# -------------------------------------------------------
resource "aws_s3_bucket" "config" {
  bucket = "trackhaul-config-logs-${var.management_account_id}"

  tags = {
    Purpose = "Config-Logs"
    GDPR    = "true"
  }
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket = aws_s3_bucket.config.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowConfigWrite"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config.arn}/AWSLogs/${var.management_account_id}/Config/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "AllowConfigCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config.arn
      },
      {
        Sid    = "DenyNonSecureTransport"
        Effect = "Deny"
        Principal = "*"
        Action   = "s3:*"
        Resource = [
          aws_s3_bucket.config.arn,
          "${aws_s3_bucket.config.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# -------------------------------------------------------
# DELIVERY CHANNEL
# Tells Config where to send configuration snapshots
# -------------------------------------------------------
resource "aws_config_delivery_channel" "this" {
  name           = "trackhaul-config-delivery"
  s3_bucket_name = aws_s3_bucket.config.id

  snapshot_delivery_properties {
    delivery_frequency = "TwentyFour_Hours"
  }

  depends_on = [aws_config_configuration_recorder.this]
}

# -------------------------------------------------------
# START THE RECORDER
# -------------------------------------------------------
resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.this]
}

# -------------------------------------------------------
# CONFIG RULES
# Each rule continuously evaluates a specific compliance check
# -------------------------------------------------------

# Rule 1 — MFA enabled for IAM console users
resource "aws_config_config_rule" "mfa_enabled" {
  name        = "mfa-enabled-for-iam-console"
  description = "Checks IAM users have MFA enabled for console access"

  source {
    owner             = "AWS"
    source_identifier = "MFA_ENABLED_FOR_IAM_CONSOLE_ACCESS"
  }

  depends_on = [aws_config_configuration_recorder_status.this]
}

# Rule 2 — No public S3 read
resource "aws_config_config_rule" "s3_public_read" {
  name        = "s3-bucket-public-read-prohibited"
  description = "Checks S3 buckets do not allow public read access"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder_status.this]
}

# Rule 3 — No public S3 write
resource "aws_config_config_rule" "s3_public_write" {
  name        = "s3-bucket-public-write-prohibited"
  description = "Checks S3 buckets do not allow public write access"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_WRITE_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder_status.this]
}

# Rule 4 — S3 encryption enforced
resource "aws_config_config_rule" "s3_encryption" {
  name        = "s3-bucket-server-side-encryption-enabled"
  description = "GDPR Article 32: Checks S3 buckets have encryption enabled"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder_status.this]
}

# Rule 5 — EBS encryption enforced
resource "aws_config_config_rule" "ebs_encryption" {
  name        = "ebs-encrypted-volumes"
  description = "GDPR Article 32: Checks EBS volumes are encrypted"

  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }

  depends_on = [aws_config_configuration_recorder_status.this]
}

# Rule 6 — RDS encryption enforced
resource "aws_config_config_rule" "rds_encryption" {
  name        = "rds-storage-encrypted"
  description = "GDPR Article 32: Checks RDS instances have storage encryption"

  source {
    owner             = "AWS"
    source_identifier = "RDS_STORAGE_ENCRYPTED"
  }

  depends_on = [aws_config_configuration_recorder_status.this]
}

# Rule 7 — CloudTrail enabled
resource "aws_config_config_rule" "cloudtrail_enabled" {
  name        = "cloudtrail-enabled"
  description = "GDPR Article 30: Checks CloudTrail is enabled"

  source {
    owner             = "AWS"
    source_identifier = "CLOUD_TRAIL_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder_status.this]
}

# Rule 8 — Root account MFA
resource "aws_config_config_rule" "root_mfa" {
  name        = "root-account-mfa-enabled"
  description = "Checks root account has MFA enabled"

  source {
    owner             = "AWS"
    source_identifier = "ROOT_ACCOUNT_MFA_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder_status.this]
}

# -------------------------------------------------------
# CONFIG AGGREGATOR
# Aggregates compliance findings from all accounts
# into the Security account
# -------------------------------------------------------
resource "aws_config_configuration_aggregator" "organization" {
  name = "trackhaul-org-aggregator"

  organization_aggregation_source {
    all_regions = false
    regions     = [var.primary_region, var.dr_region]
    role_arn    = aws_iam_role.config_aggregator.arn
  }
}

resource "aws_iam_role" "config_aggregator" {
  name = "trackhaul-config-aggregator-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "config_aggregator" {
  role       = aws_iam_role.config_aggregator.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSConfigRoleForOrganizations"
}