# modules/cloudtrail/main.tf
# Centralized CloudTrail for all TrackHaul accounts
# Logs stored in Log Archive account with Object Lock WORM
# Immutable audit trail — GDPR Article 30 compliance

# -------------------------------------------------------
# S3 BUCKET — LOG ARCHIVE
# This bucket lives in the Log Archive account
# It receives CloudTrail logs from all 5 accounts
# Object Lock prevents anyone from modifying or deleting logs
# -------------------------------------------------------
resource "aws_s3_bucket" "cloudtrail" {
  bucket = "trackhaul-cloudtrail-logs-${var.log_archive_account_id}"

  # Object Lock must be enabled at bucket creation
  # It cannot be enabled after the fact
  object_lock_enabled = true

  tags = {
    Purpose = "CloudTrail-Logs"
    GDPR    = "true"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Block all public access — logs must never be public
resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# Enable versioning — required for Object Lock
resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Object Lock — Compliance mode, 7 year retention
# This is the WORM configuration
# Once set to Compliance mode it cannot be removed
resource "aws_s3_bucket_object_lock_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    default_retention {
      mode  = "COMPLIANCE"
      years = 7
    }
  }
}

# -------------------------------------------------------
# BUCKET POLICY
# Only CloudTrail service can write to this bucket
# Only Log Archive account can read
# Nobody can delete objects
# -------------------------------------------------------
resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudTrailCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid    = "AllowCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "DenyNonSecureTransport"
        Effect = "Deny"
        Principal = "*"
        Action   = "s3:*"
        Resource = [
          aws_s3_bucket.cloudtrail.arn,
          "${aws_s3_bucket.cloudtrail.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid    = "DenyObjectDelete"
        Effect = "Deny"
        Principal = "*"
        Action = [
          "s3:DeleteObject",
          "s3:DeleteObjectVersion"
        ]
        Resource = "${aws_s3_bucket.cloudtrail.arn}/*"
      }
    ]
  })
}

# -------------------------------------------------------
# ORGANIZATION TRAIL
# One trail covering all accounts in the Organization
# This is more efficient than one trail per account
# All logs flow to the same S3 bucket
# -------------------------------------------------------
resource "aws_cloudtrail" "organization" {
  name                          = "trackhaul-organization-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  is_multi_region_trail         = true
  is_organization_trail         = true
  enable_log_file_validation    = true
  include_global_service_events = true

  tags = {
    Purpose = "Organization-Audit-Trail"
    GDPR    = "true"
  }
}
