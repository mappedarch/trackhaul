resource "aws_s3_bucket" "eval" {
  bucket = "${var.naming_prefix}-eval"

  tags = {
    Environment = var.environment
    Purpose     = "llmops-eval"
    ManagedBy   = "terraform"
  }
}

# Versioning — every dataset upload is preserved, not overwritten
resource "aws_s3_bucket_versioning" "eval" {
  bucket = aws_s3_bucket.eval.id

  versioning_configuration {
    status = "Enabled"
  }
}

# KMS encryption — same key as SSM prompts, scoped to LLMOps boundary
resource "aws_s3_bucket_server_side_encryption_configuration" "eval" {
  bucket = aws_s3_bucket.eval.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    # Prevents S3 from falling back to SSE-S3 if KMS is unavailable
    bucket_key_enabled = true
  }
}

# Block all public access — GDPR requirement
resource "aws_s3_bucket_public_access_block" "eval" {
  bucket = aws_s3_bucket.eval.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle — move eval results to Glacier after retention window
resource "aws_s3_bucket_lifecycle_configuration" "eval" {
  bucket = aws_s3_bucket.eval.id

  rule {
    id     = "eval-results-archive"
    status = "Enabled"

    filter {
      prefix = "eval-results/"
    }

    transition {
      days          = var.eval_results_retention_days
      storage_class = "GLACIER"
    }
  }

  rule {
    id     = "golden-dataset-retain"
    status = "Enabled"

    filter {
      prefix = "golden-dataset/"
    }

    # Golden dataset is never archived — it is the source of truth
    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "STANDARD_IA"
    }
  }
}
