# ---------------------------------------------------------------
# KMS Customer Managed Key — TrackHaul Event Pipeline
# One CMK covers SQS, SNS, Lambda, and CloudWatch Logs
# Key policy follows least privilege — no wildcard principals
# ---------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_kms_key" "pipeline" {
  description             = "TrackHaul ${var.environment} event pipeline encryption key"
  deletion_window_in_days = 14
  enable_key_rotation     = true  # Mandatory for regulated workloads — auto-rotates annually

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [

      # Root account full access — required, without this the key becomes unmanageable
      {
        Sid    = "EnableRootAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },

      # Lambda execution roles — decrypt only, no key management
      {
        Sid    = "AllowLambdaDecrypt"
        Effect = "Allow"
        Principal = {
          AWS = var.lambda_role_arns
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      },

      # SQS service — needs GenerateDataKey to encrypt messages on send
      {
        Sid    = "AllowSQSService"
        Effect = "Allow"
        Principal = {
          Service = "sqs.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      },

      # SNS service — needs GenerateDataKey to encrypt messages on publish
      {
        Sid    = "AllowSNSService"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      },

      # CloudWatch Logs — needs GenerateDataKey to encrypt log events
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      },

      # Step Functions — needs GenerateDataKey for execution log encryption
      {
        Sid    = "AllowStepFunctions"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowEventBridgeSQSDelivery"
        Effect = "Allow"
        Principal = {
          AWS = var.eventbridge_role_arn
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-pipeline-key"
  })
}

# Human-readable alias — used to reference the key without hardcoding ARNs
resource "aws_kms_alias" "pipeline" {
  name          = "alias/${var.project}-${var.environment}-pipeline"
  target_key_id = aws_kms_key.pipeline.key_id
}
