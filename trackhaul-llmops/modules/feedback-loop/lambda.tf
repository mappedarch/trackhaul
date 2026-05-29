# -------------------------------------------------------
# Package Lambda source files into zip archives
# -------------------------------------------------------
data "archive_file" "feedback_capture" {
  type        = "zip"
  source_file = "${path.root}/../../lambda_src/feedback_capture.py"
  output_path = "${path.module}/builds/feedback_capture.zip"
}

data "archive_file" "feedback_reingest" {
  type        = "zip"
  source_file = "${path.root}/../../lambda_src/feedback_reingest.py"
  output_path = "${path.module}/builds/feedback_reingest.zip"
}

# -------------------------------------------------------
# Feedback Capture Lambda
# Invoked by the application when a dispatcher submits feedback
# -------------------------------------------------------
resource "aws_lambda_function" "feedback_capture" {
  function_name    = "trackhaul-feedback-capture-${var.environment}"
  role             = aws_iam_role.feedback_capture.arn
  runtime          = "python3.12"
  handler          = "feedback_capture.lambda_handler"
  filename         = data.archive_file.feedback_capture.output_path
  source_code_hash = data.archive_file.feedback_capture.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      FEEDBACK_TABLE_NAME = aws_dynamodb_table.feedback.name
    }
  }

  kms_key_arn = var.kms_key_arn

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "feedback_capture" {
  name              = "/trackhaul/llm/feedback-capture/${var.environment}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}

# -------------------------------------------------------
# Feedback Reingestion Lambda
# Runs weekly — pulls approved corrections into golden dataset
# -------------------------------------------------------
resource "aws_lambda_function" "feedback_reingest" {
  function_name    = "trackhaul-feedback-reingest-${var.environment}"
  role             = aws_iam_role.feedback_reingest.arn
  runtime          = "python3.12"
  handler          = "feedback_reingest.lambda_handler"
  filename         = data.archive_file.feedback_reingest.output_path
  source_code_hash = data.archive_file.feedback_reingest.output_base64sha256
  timeout          = 120

  environment {
    variables = {
      FEEDBACK_TABLE_NAME    = aws_dynamodb_table.feedback.name
      GOLDEN_DATASET_BUCKET  = var.golden_dataset_bucket
      GOLDEN_DATASET_PREFIX  = var.golden_dataset_prefix
    }
  }

  kms_key_arn = var.kms_key_arn

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "feedback_reingest" {
  name              = "/trackhaul/llm/feedback-reingest/${var.environment}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}

# -------------------------------------------------------
# EventBridge Scheduler — weekly reingestion trigger
# Runs every Monday at 02:00 UTC
# -------------------------------------------------------
resource "aws_scheduler_schedule" "feedback_reingest" {
  name       = "trackhaul-feedback-reingest-${var.environment}"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "cron(0 2 ? * MON *)"

  target {
    arn      = aws_lambda_function.feedback_reingest.arn
    role_arn = aws_iam_role.scheduler.arn
  }
}

# EventBridge Scheduler needs permission to invoke the Lambda
resource "aws_iam_role" "scheduler" {
  name = "trackhaul-feedback-scheduler-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "scheduler" {
  name = "scheduler-invoke-policy"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.feedback_reingest.arn
    }]
  })
}
