# CMK for DynamoDB table encryption
# Automatic rotation enabled — required for GDPR audit scope
resource "aws_kms_key" "dynamodb" {
  description             = "TrackHaul DynamoDB CMK — ${var.environment}"
  deletion_window_in_days = 7
  enable_key_rotation     = true  # Rotates annually — never leave this false in prod

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Root account full access — required or the key becomes unmanageable
        Sid    = "EnableRootAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        # DynamoDB service permission to use the key
        Sid    = "AllowDynamoDB"
        Effect = "Allow"
        Principal = {
          Service = "dynamodb.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowLambdaDecrypt"
        Effect = "Allow"
        Principal = {
          AWS = var.lambda_exec_role_arn
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Project     = "trackhaul"
    Environment = var.environment
    Purpose     = "dynamodb-encryption"
  }
}

# Human-readable alias
resource "aws_kms_alias" "dynamodb" {
  name          = "alias/trackhaul-dynamodb-${var.environment}"
  target_key_id = aws_kms_key.dynamodb.key_id
}
