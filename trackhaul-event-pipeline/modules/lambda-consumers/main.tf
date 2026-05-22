# -------------------------------------------------------
# Lambda Consumers Module
# Deploys four consumer Lambdas and their SQS event source
# mappings. All functions use ReportBatchItemFailures to
# avoid reprocessing successful messages on partial failure.
# -------------------------------------------------------

locals {
  # Map of consumer name → handler path and source dir
  consumers = {
    geofence       = { handler = "handler.handler" }
    fuel_anomaly   = { handler = "handler.handler" }
    driver_scoring = { handler = "handler.handler" }
    maintenance    = { handler = "handler.handler" }
  }

  # SQS queue ARNs mapped by consumer name — used in ESM wiring
  queue_arns = {
    geofence       = var.geofence_queue_arn
    fuel_anomaly   = var.fuel_anomaly_queue_arn
    driver_scoring = var.driver_scoring_queue_arn
    maintenance    = var.maintenance_queue_arn
  }
}

# -------------------------------------------------------
# Zip each Lambda function source directory
# -------------------------------------------------------
data "archive_file" "lambda_zip" {
  for_each    = local.consumers
  type        = "zip"
  source_dir = "${path.module}/../../lambda_src/${each.key}"
  output_path = "${path.module}/builds/${each.key}.zip"
}

# -------------------------------------------------------
# IAM execution role — one per consumer (least privilege)
# -------------------------------------------------------
resource "aws_iam_role" "lambda_exec" {
  for_each = local.consumers

  name = "trackhaul-${var.environment}-${each.key}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Environment = var.environment
    Consumer    = each.key
  }
}

# -------------------------------------------------------
# CloudWatch Logs policy — scoped to this function's log group
# -------------------------------------------------------
resource "aws_iam_role_policy" "lambda_logs" {
  for_each = local.consumers

  name = "trackhaul-${var.environment}-${each.key}-logs"
  role = aws_iam_role.lambda_exec[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        # Scoped to this function only
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/trackhaul-${var.environment}-${each.key}:*"
      }
    ]
  })
}

# -------------------------------------------------------
# SQS consume policy — scoped to the specific queue
# -------------------------------------------------------
resource "aws_iam_role_policy" "lambda_sqs" {
  for_each = local.consumers

  name = "trackhaul-${var.environment}-${each.key}-sqs"
  role = aws_iam_role.lambda_exec[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = local.queue_arns[each.key]
      }
    ]
  })
}

# -------------------------------------------------------
# Step Functions invoke policy — scoped to incident state machine
# Only geofence and maintenance handlers invoke SFN
# All four roles get the policy — keeps role management uniform
# -------------------------------------------------------
resource "aws_iam_role_policy" "lambda_sfn" {
  for_each = local.consumers

  name = "trackhaul-${var.environment}-${each.key}-sfn"
  role = aws_iam_role.lambda_exec[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["states:StartExecution"]
      Resource = var.state_machine_arn
    }]
  })
}

# -------------------------------------------------------
# KMS decrypt policy — needed to read encrypted SQS messages
# -------------------------------------------------------
resource "aws_iam_role_policy" "lambda_kms" {
  for_each = local.consumers

  name = "trackhaul-${var.environment}-${each.key}-kms"
  role = aws_iam_role.lambda_exec[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = var.kms_key_arn
      }
    ]
  })
}

# -------------------------------------------------------
# Lambda log groups — explicit so retention is controlled
# -------------------------------------------------------
resource "aws_cloudwatch_log_group" "lambda_logs" {
  for_each = local.consumers

  name              = "/aws/lambda/trackhaul-${var.environment}-${each.key}"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn

  tags = {
    Environment = var.environment
    Consumer    = each.key
  }
}

# -------------------------------------------------------
# Lambda functions
# -------------------------------------------------------
resource "aws_lambda_function" "consumer" {
  for_each = local.consumers

  function_name = "trackhaul-${var.environment}-${each.key}"
  role          = aws_iam_role.lambda_exec[each.key].arn
  handler       = each.value.handler
  runtime       = "python3.12"
  timeout       = var.lambda_timeout
  filename      = data.archive_file.lambda_zip[each.key].output_path

  # Force redeploy when source changes
  source_code_hash = data.archive_file.lambda_zip[each.key].output_base64sha256

  kms_key_arn = var.kms_key_arn

  environment {
    variables = {
      ENVIRONMENT       = var.environment
      LOG_LEVEL         = "INFO"
      STATE_MACHINE_ARN = var.state_machine_arn
    }
  }

  # Depends on log group existing before function — avoids race condition
  depends_on = [aws_cloudwatch_log_group.lambda_logs]

  tags = {
    Environment = var.environment
    Consumer    = each.key
  }
}

# -------------------------------------------------------
# Event Source Mappings — SQS → Lambda
# ReportBatchItemFailures enabled on all consumers
# -------------------------------------------------------
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  for_each = local.consumers

  event_source_arn = local.queue_arns[each.key]
  function_name    = aws_lambda_function.consumer[each.key].arn
  batch_size       = var.batch_size
  enabled          = true

  # Partial batch failure — only failed messages retry, not the whole batch
  function_response_types = ["ReportBatchItemFailures"]

  scaling_config {
    maximum_concurrency = 10  # Limit concurrency per consumer — cost guard at dev stage
  }
}

# -------------------------------------------------------
# CloudWatch alarm — DLQ depth per consumer
# Alerts if any message lands in DLQ
# -------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  for_each = local.consumers

  alarm_name          = "trackhaul-${var.environment}-${each.key}-dlq-depth"
  alarm_description   = "Messages in DLQ for ${each.key} consumer — investigate immediately"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    # Derive the DLQ name from the main queue ARN convention
    # Assumes DLQ name follows pattern: <queue-name>-dlq
    QueueName = "${replace(split(":", local.queue_arns[each.key])[5], "", "")}-dlq"
  }

  tags = {
    Environment = var.environment
    Consumer    = each.key
  }
}