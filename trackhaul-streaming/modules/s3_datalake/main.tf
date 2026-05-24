resource "aws_s3_bucket" "datalake" {
  bucket = var.bucket_name

  tags = var.tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "datalake" {
  bucket = aws_s3_bucket.datalake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true # reduces KMS API calls — important at high event volume
  }
}

resource "aws_s3_bucket_versioning" "datalake" {
  bucket = aws_s3_bucket.datalake.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "datalake" {
  bucket = aws_s3_bucket.datalake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "datalake" {
  bucket = aws_s3_bucket.datalake.id

  rule {
    id     = "telemetry-tiering"
    status = "Enabled"

    filter {
      prefix = "telemetry/"
    }

    # Move to IA after 30 days — telemetry is rarely queried after a month
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Move to Glacier after 90 days — compliance retention only
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # GDPR: hard delete after 365 days
    expiration {
      days = 365
    }
  }

  rule {
    id     = "error-cleanup"
    status = "Enabled"

    filter {
      prefix = "errors/"
    }

    # Keep error files 30 days for investigation then purge
    expiration {
      days = 30
    }
  }
}