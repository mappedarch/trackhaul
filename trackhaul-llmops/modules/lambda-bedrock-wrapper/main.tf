# -------------------------------------------------------
# Zip the wrapper function from lambda_src
# -------------------------------------------------------
data "archive_file" "wrapper" {
  type        = "zip"
  source_file = "${path.module}/../../lambda_src/lambda_bedrock_wrapper.py"
  output_path = "${path.module}/../../lambda_src/lambda_bedrock_wrapper.zip"
}

data "aws_caller_identity" "current" {}

# -------------------------------------------------------
# CloudWatch Log Group — explicit retention and encryption
# Never leave log groups to default — cost and compliance risk
# -------------------------------------------------------
resource "aws_cloudwatch_log_group" "wrapper" {
  name              = "/trackhaul/llm/interactions/${var.environment}"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn

}

# -------------------------------------------------------
# IAM role — Lambda execution role
# -------------------------------------------------------
resource "aws_iam_role" "wrapper" {
  name = "trackhaul-llm-wrapper-${var.environment}"

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
# SSM read on active pointer and versioned prompts only
# Bedrock invoke on specific model only
# KMS decrypt for log encryption
# -------------------------------------------------------
resource "aws_iam_role_policy" "wrapper" {
  name = "trackhaul-llm-wrapper-policy-${var.environment}"
  role = aws_iam_role.wrapper.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMPromptRead"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          var.ssm_prompt_active_pointer_arn,
          var.ssm_prompt_version_arn
        ]
      },
      {
        Sid    = "BedrockInvoke"
        Effect = "Allow"
        Action = [
            "bedrock:InvokeModel",
            "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
            "arn:aws:bedrock:eu-central-1:${data.aws_caller_identity.current.account_id}:inference-profile/${var.bedrock_model_id}",
            "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0"
        ]
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = var.kms_key_arn
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.wrapper.arn}:*"
      },
      {
        Sid    = "CloudWatchMetrics"
        Effect = "Allow"
        Action = ["cloudwatch:PutMetricData"]
        Resource = "*"
       }
    ]
  })
}

# -------------------------------------------------------
# Lambda function
# Extension layer attached — handles SSM caching via localhost
# -------------------------------------------------------
resource "aws_lambda_function" "wrapper" {
  function_name    = "trackhaul-llm-wrapper-${var.environment}"
  role             = aws_iam_role.wrapper.arn
  filename         = data.archive_file.wrapper.output_path
  source_code_hash = data.archive_file.wrapper.output_base64sha256
  handler          = "lambda_bedrock_wrapper.handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 256

  layers = [var.extension_layer_arn]

  environment {
    variables = {
      ENVIRONMENT                = var.environment
      BEDROCK_MODEL_ID           = var.bedrock_model_id
      SSM_PROMPT_PARAMETER_NAME  = var.ssm_prompt_active_pointer_name
      SSM_PARAMETER_STORE_TTL    = tostring(var.ssm_parameter_ttl)
      SIMULATION_MODE            = tostring(var.simulation_mode)
    }
  }

  logging_config {
    log_group  = aws_cloudwatch_log_group.wrapper.name
    log_format = "JSON"
  }

  depends_on = [
    aws_cloudwatch_log_group.wrapper,
    aws_iam_role_policy.wrapper
  ]

}
