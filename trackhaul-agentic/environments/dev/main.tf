# KMS key scoped to the agentic boundary
resource "aws_kms_key" "agentic" {
  description             = "TrackHaul agentic layer encryption key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = local.common_tags
}

resource "aws_kms_alias" "agentic" {
  name          = "alias/trackhaul-agentic-${var.environment}"
  target_key_id = aws_kms_key.agentic.key_id
}

# Agent queue — SQS + DLQ + Lambda + IAM
module "agent_queue" {
  source = "../../modules/agent-queue"

  environment                    = var.environment
  kms_key_arn                    = aws_kms_key.agentic.arn
  lambda_reserved_concurrency    = var.lambda_reserved_concurrency
  lambda_src_path = "${path.module}/../../lambda_src/agent_handler.zip"
}