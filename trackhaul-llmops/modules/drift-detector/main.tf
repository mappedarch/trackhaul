# -------------------------------------------------------
# Zip the drift detector Lambda from lambda_src
# -------------------------------------------------------
data "archive_file" "drift_detector" {
  type        = "zip"
  source_file = "${path.module}/../../lambda_src/lambda_drift_detector.py"
  output_path = "${path.module}/../../lambda_src/lambda_drift_detector.zip"
}

# -------------------------------------------------------
# SNS topic — drift alerts
# Subscriptions managed outside Terraform (email, Slack)
# -------------------------------------------------------
resource "aws_sns_topic" "drift_alerts" {
  name              = "${var.naming_prefix}-drift-alerts"
  kms_master_key_id = var.kms_key_arn
}

# -------------------------------------------------------
# CloudWatch Log Group — explicit retention
# Never leave log groups to default — cost and compliance risk
# -------------------------------------------------------
resource "aws_cloudwatch_log_group" "drift_detector" {
  name              = "/trackhaul/llm/drift-detector/${var.environment}"
  retention_in_days = 90
  kms_key_id        = var.kms_key_arn
}

# -------------------------------------------------------
# IAM role — drift detector execution role
# -------------------------------------------------------
resource "aws_iam_role" "drift_detector" {
  name = "${var.naming_prefix}-drift-detector"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# -------------------------------------------------------
# IAM policy — least privilege
# CloudWatch read for metric statistics
# CloudWatch write for DriftDetected metric
# SSM read/write for consecutive drift counter only
# SNS publish to drift alerts topic only
# -------------------------------------------------------
resource "aws_iam_role_policy" "drift_detector" {
  name = "${var.naming_prefix}-drift-detector-policy"
  role = aws_iam_role.drift_detector.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchMetricsRead"
        Effect = "Allow"
        Action = ["cloudwatch:GetMetricStatistics"]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchMetricsWrite"
        Effect = "Allow"
        Action = ["cloudwatch:PutMetricData"]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:CreateLogGroup"
        ]
        Resource = "${aws_cloudwatch_log_group.drift_detector.arn}:*"
      },
      {
        Sid    = "SSMDriftCounter"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:PutParameter"
        ]
        # Scoped to drift counter path only — not all SSM parameters
        Resource = "arn:aws:ssm:eu-central-1:*:parameter/trackhaul/llmops/drift-counter/*"
      },
      {
        Sid      = "SNSPublish"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.drift_alerts.arn
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = var.kms_key_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "drift_detector_basic" {
  role       = aws_iam_role.drift_detector.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# -------------------------------------------------------
# Lambda function — drift detector
# -------------------------------------------------------
resource "aws_lambda_function" "drift_detector" {
  function_name    = "${var.naming_prefix}-drift-detector"
  role             = aws_iam_role.drift_detector.arn
  filename         = data.archive_file.drift_detector.output_path
  source_code_hash = data.archive_file.drift_detector.output_base64sha256
  handler          = "lambda_drift_detector.handler"
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 128

  environment {
    variables = {
      ENVIRONMENT        = var.environment
      METRICS_NAMESPACE  = "TrackHaul/LLMOps"
      SNS_TOPIC_ARN      = aws_sns_topic.drift_alerts.arn
      PROMPT_VERSION     = var.prompt_version
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.drift_detector,
    aws_iam_role_policy.drift_detector
  ]
}

# -------------------------------------------------------
# EventBridge Scheduler — daily at 06:00 UTC
# Runs after overnight traffic has populated the daily metric bucket
# -------------------------------------------------------
resource "aws_scheduler_schedule" "drift_detector_daily" {
  name       = "${var.naming_prefix}-drift-detector-daily"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "cron(0 6 * * ? *)"

  target {
    arn      = aws_lambda_function.drift_detector.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ "source": "eventbridge-scheduler" })
  }
}

# -------------------------------------------------------
# IAM role — EventBridge Scheduler execution role
# Scoped to invoke this Lambda only
# -------------------------------------------------------
resource "aws_iam_role" "scheduler" {
  name = "${var.naming_prefix}-drift-scheduler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  name = "${var.naming_prefix}-drift-scheduler-policy"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "InvokeDriftDetector"
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = aws_lambda_function.drift_detector.arn
    }]
  })
}

# -------------------------------------------------------
# Lambda permission — allow EventBridge Scheduler to invoke
# -------------------------------------------------------
resource "aws_lambda_permission" "scheduler" {
  statement_id  = "AllowEventBridgeScheduler"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.drift_detector.function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = aws_scheduler_schedule.drift_detector_daily.arn
}
