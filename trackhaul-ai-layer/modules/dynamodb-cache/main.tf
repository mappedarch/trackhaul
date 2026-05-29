resource "aws_dynamodb_table" "rag_cache" {
  name         = "${var.project}-${var.environment}-rag-cache"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "query_hash"

  attribute {
    name = "query_hash"
    type = "S"
  }

  # TTL attribute — DynamoDB auto-deletes expired items
  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  tags = {
    Project     = var.project
    Environment = var.environment
    Purpose     = "rag-query-cache"
  }
}
