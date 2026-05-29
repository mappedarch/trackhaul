resource "aws_dynamodb_table" "feedback" {
  name         = "trackhaul-llm-feedback-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "interaction_id"
  range_key    = "timestamp"

  attribute {
    name = "interaction_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  attribute {
    name = "review_status"
    type = "S"
  }

  attribute {
    name = "eval_candidate"
    type = "S"
  }

  # Allows reviewer dashboard to query all pending items
  global_secondary_index {
    name            = "review-status-index"
    hash_key        = "review_status"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  # Allows reingestion Lambda to query approved corrections
  global_secondary_index {
    name            = "eval-candidate-index"
    hash_key        = "eval_candidate"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = var.tags
}
