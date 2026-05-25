terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  common_tags = {
    Project     = "trackhaul"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

module "kinesis" {
  source = "../../modules/kinesis"

  stream_name            = "trackhaul-telemetry-${var.environment}"
  shard_count            = var.shard_count
  retention_period_hours = var.retention_period_hours
  kms_key_arn            = module.kms_kinesis.key_arn
  environment            = var.environment
  tags                   = local.common_tags
}

module "kinesis_consumer" {
  source = "../../modules/kinesis_consumer"

  stream_arn             = module.kinesis.stream_arn
  stream_name            = module.kinesis.stream_name
  lambda_zip_path        = "${path.module}/../../lambda_src/telemetry_consumer/telemetry_consumer.zip"
  anomaly_event_bus_name = "trackhaul-fleet-events"
  kms_key_arn            = module.kms_kinesis.key_arn
  environment            = var.environment
  tags                   = local.common_tags
}

module "kms_s3" {
  source = "../../modules/kms"

  alias_name                = "trackhaul-s3-datalake-${var.environment}"
  description               = "KMS key for TrackHaul S3 data lake"
  deletion_window_in_days   = 30
  allowed_service_principal = "s3.amazonaws.com"
  allowed_iam_arns          = []
  aws_account_id            = var.aws_account_id
  environment               = var.environment
  tags                      = local.common_tags
}

module "s3_datalake" {
  source = "../../modules/s3_datalake"

  bucket_name = "trackhaul-telemetry-datalake-${var.aws_account_id}-${var.environment}"
  kms_key_arn = module.kms_s3.key_arn
  environment = var.environment
  tags        = local.common_tags
}

module "glue" {
  source = "../../modules/glue"

  database_name = "trackhaul_telemetry_${var.environment}"
  table_name    = "fleet_telemetry"
  bucket_name   = module.s3_datalake.bucket_name
  environment   = var.environment
  tags          = local.common_tags
}

module "firehose" {
  source = "../../modules/firehose"

  kinesis_stream_arn  = module.kinesis.stream_arn
  kinesis_stream_name = module.kinesis.stream_name
  s3_bucket_arn       = module.s3_datalake.bucket_arn
  kms_key_arn         = module.kms_s3.key_arn
  kinesis_kms_key_arn = module.kms_kinesis.key_arn
  glue_database_name  = module.glue.database_name
  glue_table_name     = module.glue.table_name
  aws_region          = var.aws_region
  environment         = var.environment
  tags                = local.common_tags
}

module "kms_kinesis" {
  source = "../../modules/kms"

  alias_name                = "trackhaul-kinesis-${var.environment}"
  description               = "KMS key for TrackHaul Kinesis telemetry stream"
  deletion_window_in_days   = 30
  allowed_service_principal = "kinesis.amazonaws.com"
  allowed_iam_arns          = [module.firehose.firehose_role_arn]
  aws_account_id            = var.aws_account_id
  environment               = var.environment
  tags                      = local.common_tags
}