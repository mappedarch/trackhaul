resource "aws_dynamodb_table" "vehicles" {
  name         = "${var.project}-vehicles-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"

  attribute {
    name = "PK"
    type = "S"
  }

  # GSI attributes must be declared here even though they are
  # regular item attributes — DynamoDB requires this
  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "region"
    type = "S"
  }

  # Query vehicles by operational status (active / inactive / maintenance)
  global_secondary_index {
    name            = "StatusIndex"
    hash_key        = "status"
    projection_type = "ALL"
  }

  # Query vehicles by operating region (DE / PL / NL)
  global_secondary_index {
    name            = "RegionIndex"
    hash_key        = "region"
    projection_type = "ALL"
  }

  # Protect production data from accidental terraform destroy
  lifecycle {
    prevent_destroy = false # Set to true in prod
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # KMS encryption — CMK managed outside this module, ARN passed in
  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }
}