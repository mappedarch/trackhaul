terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.6"
}

provider "aws" {
  region = "eu-central-1"
}

# KMS CMK for DynamoDB encryption — must be created first
module "kms" {
  source      = "../../modules/kms"
  environment = var.environment
  account_id  = var.account_id
  lambda_exec_role_arn = module.iam.lambda_exec_role_arn
}

# DynamoDB — encrypted with CMK from KMS module
module "dynamodb" {
  source      = "../../modules/dynamodb"
  environment = var.environment
  project     = var.project
  kms_key_arn = module.kms.key_arn
}

# IAM — execution role and all policies in one place
module "iam" {
  source             = "../../modules/iam"
  function_name      = "trackhaul-get-vehicle-${var.environment}"
  environment        = var.environment
  aws_region         = "eu-central-1"
  account_id         = var.account_id
  dynamodb_table_arn = module.dynamodb.table_arn
  kms_key_arn        = module.kms.key_arn
}

# Lambda — role ARN injected from IAM module
module "lambda_get_vehicle" {
  source                    = "../../modules/lambda"
  function_name             = "trackhaul-get-vehicle-${var.environment}"
  handler                   = "get_vehicle.handler"
  source_dir                = "${path.module}/../../lambda_src"
  environment               = var.environment
  stage_name                = var.environment
  api_gateway_execution_arn = module.api_gateway.execution_arn
  kms_key_arn               = module.kms.key_arn 
  dynamodb_table_name       = module.dynamodb.table_name
  execution_role_arn        = module.iam.lambda_exec_role_arn
  environment_variables = {
    DYNAMODB_TABLE_NAME = module.dynamodb.table_name
  }
}

module "api_gateway" {
  source                  = "../../modules/api_gateway"
  api_name                = "trackhaul-fleet-api"
  stage_name              = var.environment
  environment             = var.environment
  throttling_rate_limit   = 100
  throttling_burst_limit  = 50
  get_vehicle_invoke_arn  = module.lambda_get_vehicle.invoke_arn
  user_pool_arn           = module.cognito.user_pool_arn
}

module "cognito" {
  source      = "../../modules/cognito"
  project     = var.project
  environment = var.environment
}
