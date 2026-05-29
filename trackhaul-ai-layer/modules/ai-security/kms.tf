# -------------------------------------------------------
# KMS CMK — S3 Knowledge Base source bucket
# Used by: S3 server-side encryption, Bedrock KB reads
# -------------------------------------------------------
resource "aws_kms_key" "s3_kb" {
  description             = "${var.project}-${var.environment} S3 KB source CMK"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Root account full control — required or the key becomes unmanageable
        Sid    = "RootAccess"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        # Bedrock KB role needs Decrypt and GenerateDataKey to read S3 objects
        Sid    = "BedrockKBAccess"
        Effect = "Allow"
        Principal = { Service = "bedrock.amazonaws.com" }
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = "*"
        Condition = {
          StringEquals = { "aws:SourceAccount" = var.account_id }
        }
      },
      {
        # S3 needs GenerateDataKey to write encrypted objects
        Sid    = "S3ServiceAccess"
        Effect = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = "*"
      }
    ]
  })

  tags = {
    Project     = var.project
    Environment = var.environment
    Purpose     = "s3-kb-encryption"
  }
}

resource "aws_kms_alias" "s3_kb" {
  name          = "alias/${var.project}-s3-kb-${var.environment}"
  target_key_id = aws_kms_key.s3_kb.key_id
}

# -------------------------------------------------------
# KMS CMK — DynamoDB (RAG cache + token tracker)
# -------------------------------------------------------
resource "aws_kms_key" "dynamodb" {
  description             = "${var.project}-${var.environment} DynamoDB CMK"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RootAccess"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        # DynamoDB service needs these to encrypt/decrypt table data
        Sid    = "DynamoDBServiceAccess"
        Effect = "Allow"
        Principal = { Service = "dynamodb.amazonaws.com" }
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = "*"
      }
    ]
  })

  tags = {
    Project     = var.project
    Environment = var.environment
    Purpose     = "dynamodb-encryption"
  }
}

resource "aws_kms_alias" "dynamodb" {
  name          = "alias/${var.project}-ai-dynamodb-${var.environment}"
  target_key_id = aws_kms_key.dynamodb.key_id
}

# -------------------------------------------------------
# KMS CMK — CloudWatch Logs (Lambda function logs)
# Gotcha: CloudWatch Logs needs an explicit key policy grant.
# IAM alone is not sufficient — the logs.amazonaws.com principal
# must be in the key policy or log group encryption will fail silently.
# -------------------------------------------------------
resource "aws_kms_key" "cloudwatch" {
  description             = "${var.project}-${var.environment} CloudWatch Logs CMK"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RootAccess"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        # Region-scoped — CloudWatch Logs principal is region-specific
        Sid    = "CloudWatchLogsAccess"
        Effect = "Allow"
        Principal = { Service = "logs.${var.aws_region}.amazonaws.com" }
        Action   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${var.account_id}:*"
          }
        }
      }
    ]
  })

  tags = {
    Project     = var.project
    Environment = var.environment
    Purpose     = "cloudwatch-logs-encryption"
  }
}

resource "aws_kms_alias" "cloudwatch" {
  name          = "alias/${var.project}-cloudwatch-${var.environment}"
  target_key_id = aws_kms_key.cloudwatch.key_id
}