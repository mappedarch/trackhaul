# ---------------------------------------------------------------
# Construct Lambda ARNs from naming convention
# Avoids circular dependency between lambda_consumers and step_functions
# ---------------------------------------------------------------
locals {
  diagnose_lambda_arn    = "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:trackhaul-${var.environment}-maintenance"
  maintenance_lambda_arn = "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:trackhaul-${var.environment}-maintenance"
  alert_lambda_arn       = "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:trackhaul-${var.environment}-fuel_anomaly"
}

resource "aws_cloudwatch_log_group" "sfn_logs" {
  name              = "/aws/states/${var.project}-${var.environment}-incident"
  retention_in_days = 90
  kms_key_id        = var.kms_key_arn
}

resource "aws_sfn_state_machine" "incident" {
  name     = "${var.project}-${var.environment}-incident-workflow"
  role_arn = aws_iam_role.sfn_role.arn
  type     = "STANDARD" # Exactly-once, full audit history — required for GDPR

  # Interpolate Lambda ARNs and SNS topic ARNs into state machine at deploy time
  definition = templatefile("${path.module}/state_machine.json", {
    diagnose_lambda_arn          = local.diagnose_lambda_arn
    maintenance_lambda_arn       = local.maintenance_lambda_arn
    alert_lambda_arn             = local.alert_lambda_arn
    critical_alerts_topic_arn    = var.critical_alerts_topic_arn
    maintenance_alerts_topic_arn = var.maintenance_alerts_topic_arn
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn_logs.arn}:*"
    include_execution_data = true   # PROD: set to false — state input captured at volume risks data exposure   # Captures input/output per state — critical for GDPR audit
    level                  = "ALL"
  }

  tracing_configuration {
    enabled = true # X-Ray tracing
  }
}

resource "aws_iam_role" "sfn_role" {
  name = "${var.project}-${var.environment}-sfn-incident-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "sfn_invoke_lambda" {
  name = "invoke-incident-lambdas"
  role = aws_iam_role.sfn_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["lambda:InvokeFunction"]
        # Scoped to only the two Lambdas this workflow needs
        Resource = [
          local.diagnose_lambda_arn,
          local.alert_lambda_arn
        ]
      },
      {
        # Allow Step Functions to publish to both alert topics
        Effect = "Allow"
        Action = ["sns:Publish"]
        Resource = [
          var.critical_alerts_topic_arn,
          var.maintenance_alerts_topic_arn
        ]
      },
      {
        # CloudWatch logging for execution history
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:PutLogEvents",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = var.kms_key_arn
      }
    ]
  })
}