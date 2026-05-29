resource "aws_lambda_function" "fleet_intelligence" {
  function_name    = "${var.project}-dev-fleet-intelligence"
  role             = var.lambda_role_arn
  handler          = "fleet_intelligence_handler.lambda_handler"
  runtime          = "python3.12"
  filename         = var.lambda_zip_path
  source_code_hash = filebase64sha256(var.lambda_zip_path)
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      DYNAMODB_TABLE        = "trackhaul-vehicles-dev"
      KNOWLEDGE_BASE_ID     = var.knowledge_base_id
      CIRCUIT_BREAKER_TABLE = "trackhaul-dev-circuit-breaker"
      MODEL_ID              = "eu.anthropic.claude-sonnet-4-5-20250929-v1:0"
      MAX_KB_RESULTS        = "3"
      MAX_TRUCKS            = "20"
      GUARDRAIL_ID          = var.guardrail_id
      GUARDRAIL_VERSION     = var.guardrail_version
    }
  }

  tags = {
    Project     = var.project
    Environment = "dev"
  }
}