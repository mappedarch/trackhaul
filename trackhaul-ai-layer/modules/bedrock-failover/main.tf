resource "aws_dynamodb_table" "circuit_breaker" {
  name         = "${var.project}-${var.environment}-circuit-breaker"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "region"

  attribute {
    name = "region"
    type = "S"
  }

  ttl {
    attribute_name = "reset_at"
    enabled        = true
  }

  tags = {
    Project     = var.project
    Environment = var.environment
    Purpose     = "bedrock-circuit-breaker"
  }
}
