terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.49"
    }
    pinecone = {
      source  = "pinecone-io/pinecone"
      version = "~> 0.7"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "pinecone" {
  api_key = var.pinecone_api_key
}

data "aws_secretsmanager_secret" "pinecone" {
  name = "trackhaul/dev/pinecone-api-key"
}

data "aws_kms_key" "fleet_api_dynamodb" {
  key_id = "alias/trackhaul-dynamodb-dev"
}

# -------------------------------------------------------
# Security module must be created first — other modules
# depend on the KMS keys it outputs
# -------------------------------------------------------
module "ai_security" {
  source                     = "../../modules/ai-security"
  project                    = "trackhaul"
  environment                = var.environment
  aws_region                 = var.aws_region
  account_id                 = var.account_id
  vehicles_table_kms_key_arn = data.aws_kms_key.fleet_api_dynamodb.arn
}

module "s3_kb_source" {
  source      = "../../modules/s3-kb-source"
  environment = var.environment
  aws_region  = var.aws_region
  kms_key_arn = module.ai_security.s3_kb_kms_key_arn
}

module "pinecone" {
  source      = "../../modules/pinecone"
  environment = var.environment
}

module "bedrock_kb" {
  source              = "../../modules/bedrock-kb"
  environment         = var.environment
  account_id          = var.account_id
  aws_region          = var.aws_region
  s3_bucket_arn       = module.s3_kb_source.bucket_arn
  pinecone_index_name = module.pinecone.index_name
  pinecone_host       = module.pinecone.index_host
  pinecone_secret_arn = data.aws_secretsmanager_secret.pinecone.arn
}

module "dynamodb_cache" {
  source      = "../../modules/dynamodb-cache"
  project     = "trackhaul"
  environment = var.environment
  kms_key_arn = module.ai_security.dynamodb_kms_key_arn
}

module "bedrock_guardrails" {
  source      = "../../modules/bedrock-guardrails"
  project     = "trackhaul"
  environment = var.environment
}

module "token_tracker" {
  source      = "../../modules/token-tracker"
  project     = "trackhaul"
  environment = var.environment
  # CMK created in ai-security — replaces the old data source lookup
  kms_key_arn = module.ai_security.dynamodb_kms_key_arn
}

module "bedrock_failover" {
  source      = "../../modules/bedrock-failover"
  project     = var.project
  environment = var.environment
}
module "lambda_fleet_intelligence" {
  source            = "../../modules/lambda-fleet-intelligence"
  project           = "trackhaul"
  aws_region        = var.aws_region
  lambda_role_arn   = module.ai_security.fleet_intelligence_lambda_role_arn
  lambda_zip_path   = "${path.module}/../../lambda_src/package/fleet_intelligence.zip"
  knowledge_base_id = "G8TARXJU9J"
  guardrail_id      = module.bedrock_guardrails.guardrail_id
  guardrail_version = module.bedrock_guardrails.guardrail_version
}