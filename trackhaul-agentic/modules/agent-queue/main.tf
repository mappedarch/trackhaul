locals {
  name_prefix = "trackhaul-${var.environment}"
}

# -------------------------------------------------------------------
# Dead Letter Queue — receives messages after 3 failed processing attempts
# -------------------------------------------------------------------
resource "aws_sqs_queue" "incident_agent_dlq" {
  name                       = "${local.name_prefix}-incident-agent-dlq"
  message_retention_seconds  = var.dlq_message_retention_seconds
  kms_master_key_id          = var.kms_key_arn
}

# -------------------------------------------------------------------
# Main incident queue — absorbs burst from EventBridge at vehicle scale
# -------------------------------------------------------------------
resource "aws_sqs_queue" "incident_agent" {
  name                       = "${local.name_prefix}-incident-agent-queue"
  visibility_timeout_seconds = var.sqs_visibility_timeout_seconds
  message_retention_seconds  = var.sqs_message_retention_seconds
  kms_master_key_id          = var.kms_key_arn

  # After 3 failed attempts, message moves to DLQ
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.incident_agent_dlq.arn
    maxReceiveCount     = 3
  })
}

# -------------------------------------------------------------------
# IAM role for the agent Lambda
# -------------------------------------------------------------------
resource "aws_iam_role" "agent_handler" {
  name = "${local.name_prefix}-agent-handler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Basic Lambda execution — CloudWatch Logs only
resource "aws_iam_role_policy_attachment" "agent_handler_basic" {
  role       = aws_iam_role.agent_handler.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# SQS read permissions — scoped to this queue only
resource "aws_iam_role_policy" "agent_handler_sqs" {
  name = "${local.name_prefix}-agent-handler-sqs"
  role = aws_iam_role.agent_handler.id

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
        Resource = aws_sqs_queue.incident_agent.arn
      }
    ]
  })
}

# KMS permissions — decrypt SQS messages and Lambda environment
resource "aws_iam_role_policy" "agent_handler_kms" {
  name = "${local.name_prefix}-agent-handler-kms"
  role = aws_iam_role.agent_handler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
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

# -------------------------------------------------------------------
# Lambda function — agent orchestrator
# -------------------------------------------------------------------
resource "aws_lambda_function" "agent_handler" {
  function_name    = "${local.name_prefix}-agent-handler"
  role             = aws_iam_role.agent_handler.arn
  runtime          = "python3.12"
  handler          = "agent_handler.handler"
  filename         = var.lambda_src_path
  source_code_hash = filebase64sha256(var.lambda_src_path)
  timeout          = var.lambda_timeout_seconds

  environment {
    variables = {
      ENVIRONMENT = var.environment
      LOG_LEVEL   = "INFO"
    }
  }

  kms_key_arn = var.kms_key_arn
}

# -------------------------------------------------------------------
# SQS → Lambda event source mapping
# Batch size 1 — one incident per agent run, clean failure isolation
# -------------------------------------------------------------------
resource "aws_lambda_event_source_mapping" "sqs_to_agent" {
  event_source_arn = aws_sqs_queue.incident_agent.arn
  function_name    = aws_lambda_function.agent_handler.arn
  batch_size       = 1

}