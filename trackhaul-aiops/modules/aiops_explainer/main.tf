# -------------------------------------------------------
# CloudWatch Log Group — custom log group for explanation output
# Explicit retention — never leave this at default (never expires = unbounded cost)
# -------------------------------------------------------
resource "aws_cloudwatch_log_group" "aiops_explainer" {
  name              = "/trackhaul/aiops/explainer/${var.environment}"
  retention_in_days = var.log_retention_days
}

# Lambda default log group — must exist before Lambda runs
# Without this, Lambda silently fails to log if it cannot create the group
resource "aws_cloudwatch_log_group" "lambda_default" {
  name              = "/aws/lambda/trackhaul-${var.environment}-aiops-explainer"
  retention_in_days = var.log_retention_days
}

# -------------------------------------------------------
# IAM Role — Lambda execution
# -------------------------------------------------------
resource "aws_iam_role" "aiops_explainer" {
  name = "trackhaul-${var.environment}-aiops-explainer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# CloudWatch Logs — both custom and Lambda default log groups
resource "aws_iam_role_policy" "lambda_logs" {
  name = "trackhaul-${var.environment}-aiops-logs-policy"
  role = aws_iam_role.aiops_explainer.id

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
        Resource = [
          "${aws_cloudwatch_log_group.aiops_explainer.arn}:*",
          "${aws_cloudwatch_log_group.lambda_default.arn}:*"
        ]
      }
    ]
  })
}

# Bedrock — inference profile + all EU regions the cross-region profile may route to
resource "aws_iam_role_policy" "bedrock_invoke" {
  name = "trackhaul-${var.environment}-aiops-bedrock-policy"
  role = aws_iam_role.aiops_explainer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["bedrock:InvokeModel"]
      Resource = [
        "arn:aws:bedrock:${var.bedrock_region}:${var.aws_account_id}:inference-profile/${var.bedrock_model_id}",
        "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0"
      ]
    }]
  })
}

# -------------------------------------------------------
# Lambda package — zipped from local source
# -------------------------------------------------------
data "archive_file" "aiops_explainer" {
  type        = "zip"
  source_file = "${path.root}/../../lambda_src/aiops_explainer/handler.py"
  output_path = "${path.root}/../../lambda_src/aiops_explainer/aiops_explainer.zip"
}

# -------------------------------------------------------
# Lambda Function
# -------------------------------------------------------
resource "aws_lambda_function" "aiops_explainer" {
  function_name    = "trackhaul-${var.environment}-aiops-explainer"
  role             = aws_iam_role.aiops_explainer.arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.aiops_explainer.output_path
  source_code_hash = data.archive_file.aiops_explainer.output_base64sha256
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_mb

  environment {
    variables = {
      BEDROCK_REGION        = var.bedrock_region
      BEDROCK_MODEL_ID      = var.bedrock_model_id
      EXPLANATION_LOG_GROUP = aws_cloudwatch_log_group.aiops_explainer.name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.aiops_explainer,
    aws_cloudwatch_log_group.lambda_default,
    aws_iam_role_policy.lambda_logs,
    aws_iam_role_policy.bedrock_invoke
  ]
}

# -------------------------------------------------------
# EventBridge Rule — triggers explainer on anomaly events
# -------------------------------------------------------
resource "aws_cloudwatch_event_rule" "anomaly_trigger" {
  name           = "trackhaul-${var.environment}-aiops-anomaly-trigger"
  description    = "Triggers AIOps explainer Lambda on fleet anomaly events"
  event_bus_name = var.event_bus_name

  event_pattern = jsonencode({
    source      = ["trackhaul.telemetry"]
    detail-type = ["fuel_anomaly", "engine_fault", "harsh_braking", "geofence_breach"]
  })
}

resource "aws_cloudwatch_event_target" "aiops_explainer" {
  rule           = aws_cloudwatch_event_rule.anomaly_trigger.name
  event_bus_name = var.event_bus_name
  target_id      = "aiops-explainer-lambda"
  arn            = aws_lambda_function.aiops_explainer.arn
}

# Permission for EventBridge to invoke the Lambda
resource "aws_lambda_permission" "eventbridge_invoke" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.aiops_explainer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.anomaly_trigger.arn
}
