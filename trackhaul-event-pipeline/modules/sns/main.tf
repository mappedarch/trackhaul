# ---------------------------------------------------------------
# SNS Topics — TrackHaul operational alerting
# Two topics: critical alerts and maintenance alerts
# KMS encrypted, email subscriptions for dev
# ---------------------------------------------------------------

resource "aws_sns_topic" "critical_alerts" {
  name              = "${var.project}-${var.environment}-critical-alerts"
  kms_master_key_id = var.kms_key_arn

  tags = var.tags
}

resource "aws_sns_topic" "maintenance_alerts" {
  name              = "${var.project}-${var.environment}-maintenance-alerts"
  kms_master_key_id = var.kms_key_arn

  tags = var.tags
}


resource "aws_sns_topic_subscription" "critical_email" {
  topic_arn = aws_sns_topic.critical_alerts.arn
  protocol  = "email"
  endpoint  = "nititek@outlook.com"
}

resource "aws_sns_topic_subscription" "maintenance_email" {
  topic_arn = aws_sns_topic.maintenance_alerts.arn
  protocol  = "email"
  endpoint  = "nititek@outlook.com"
}

# ---------------------------------------------------------------
# Topic policy — allows Step Functions to publish
# Locked to this account only
# ---------------------------------------------------------------

data "aws_caller_identity" "current" {}

resource "aws_sns_topic_policy" "critical_alerts" {
  arn = aws_sns_topic.critical_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowStepFunctionsPublish"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.critical_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

resource "aws_sns_topic_policy" "maintenance_alerts" {
  arn = aws_sns_topic.maintenance_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowStepFunctionsPublish"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.maintenance_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}