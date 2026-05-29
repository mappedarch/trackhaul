resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "kb_source" {
  bucket        = "trackhaul-kb-source-${var.environment}-${random_id.suffix.hex}"
  force_destroy = true

  tags = {
    Project     = "trackhaul"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "kb_source" {
  bucket                  = aws_s3_bucket.kb_source.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "kb_source" {
  bucket = aws_s3_bucket.kb_source.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    # Prevents S3 from falling back to AWS-managed key if CMK is unavailable
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_policy" "enforce_tls" {
  bucket = aws_s3_bucket.kb_source.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyNonTLS"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [
        aws_s3_bucket.kb_source.arn,
        "${aws_s3_bucket.kb_source.arn}/*"
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}