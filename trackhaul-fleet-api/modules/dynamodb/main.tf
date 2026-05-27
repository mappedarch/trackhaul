resource "aws_dynamodb_table" "vehicles" {
  name         = "${var.project}-vehicles-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "region"
    type = "S"
  }

  # Added for hybrid RAG query pattern — record type per truck
  attribute {
    name = "truck_id"
    type = "S"
  }

  attribute {
    name = "record_type"
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

  # Query all records of a specific type for a specific truck
  # e.g. all FUEL records for TH-1023, all EVENT records for TH-4821
  global_secondary_index {
    name            = "TruckRecordTypeIndex"
    hash_key        = "truck_id"
    range_key       = "record_type"
    projection_type = "ALL"
  }

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

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }
}
