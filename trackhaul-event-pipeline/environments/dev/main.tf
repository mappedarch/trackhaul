terraform {
  required_version = ">= 1.6.0"

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

# ---------------------------------------------------------------
# KMS — must be created first, all other modules depend on it
# Lambda role ARNs are constructed from naming convention to
# avoid circular dependency with lambda_consumers module
# ---------------------------------------------------------------

locals {
  consumers = ["geofence", "fuel_anomaly", "driver_scoring", "maintenance"]

  # Construct Lambda role ARNs from naming convention
  # Matches the role names in lambda-consumers/main.tf
  lambda_role_arns = [
    for consumer in local.consumers :
    "arn:aws:iam::${var.aws_account_id}:role/trackhaul-${var.environment}-${consumer}-lambda-role"
  ]
}

module "kms" {
  source = "../../modules/kms"

  project          = var.project
  environment      = var.environment
  lambda_role_arns = local.lambda_role_arns

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

module "eventbridge" {
  source = "../../modules/eventbridge"

  project                = var.project
  environment            = var.environment
  enable_archive         = true
  archive_retention_days = 90

  geofence_queue_arn       = module.sqs["geofence"].queue_arn
  fuel_anomaly_queue_arn   = module.sqs["fuel_anomaly"].queue_arn
  driver_scoring_queue_arn = module.sqs["driver_scoring"].queue_arn
  maintenance_queue_arn    = module.sqs["maintenance"].queue_arn

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

module "sqs" {
  source   = "../../modules/sqs"
  for_each = toset(local.consumers)

  consumer_name = each.key
  environment   = var.environment
  project       = var.project

  visibility_timeout_seconds = 180
  message_retention_seconds  = 86400

  max_receive_count = 3
  kms_key_arn       = module.kms.key_arn

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

module "lambda_consumers" {
  source = "../../modules/lambda-consumers"

  environment = var.environment
  aws_region  = var.aws_region
  kms_key_arn = module.kms.key_arn

  geofence_queue_arn       = module.sqs["geofence"].queue_arn
  fuel_anomaly_queue_arn   = module.sqs["fuel_anomaly"].queue_arn
  driver_scoring_queue_arn = module.sqs["driver_scoring"].queue_arn
  maintenance_queue_arn    = module.sqs["maintenance"].queue_arn

  state_machine_arn = module.step_functions.state_machine_arn
}

module "step_functions" {
  source = "../../modules/step-functions"

  project        = var.project
  environment    = var.environment
  kms_key_arn    = module.kms.key_arn
  aws_region     = var.aws_region
  aws_account_id = var.aws_account_id

  critical_alerts_topic_arn    = module.sns.critical_alerts_arn
  maintenance_alerts_topic_arn = module.sns.maintenance_alerts_arn
}

module "sns" {
  source = "../../modules/sns"

  project     = var.project
  environment = var.environment
  kms_key_arn = module.kms.key_arn
  ops_email   = var.ops_email

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
