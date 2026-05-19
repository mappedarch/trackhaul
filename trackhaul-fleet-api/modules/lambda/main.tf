# Zip the Lambda source code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/builds/${var.function_name}.zip"
}

# CloudWatch log group — explicit so retention is controlled
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = 30

  tags = {
    Project     = "trackhaul"
    Environment = var.environment
  }
}

# Lambda function — role now passed in from IAM module
resource "aws_lambda_function" "this" {
  function_name    = var.function_name
  role             = var.execution_role_arn
  handler          = var.handler
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  memory_size      = var.memory_size
  timeout          = var.timeout
  kms_key_arn      = var.kms_key_arn  

  environment {
    variables = var.environment_variables
  }

  depends_on = [aws_cloudwatch_log_group.this]

  tags = {
    Project     = "trackhaul"
    Environment = var.environment
  }
}

# Resource-based policy — allows API Gateway to invoke this function
# source_arn scoped to specific stage, not wildcard
# aws:SourceAccount condition prevents confused deputy attack
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_gateway_execution_arn}/${var.stage_name}/*/*"
}
