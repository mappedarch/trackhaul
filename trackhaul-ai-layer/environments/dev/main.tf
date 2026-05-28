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

data "aws_kms_key" "dynamodb" {
  key_id = "alias/trackhaul-dynamodb-dev"
}

module "s3_kb_source" {
  source      = "../../modules/s3-kb-source"
  environment = var.environment
  aws_region  = var.aws_region
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
  kms_key_arn = data.aws_kms_key.dynamodb.arn
}

module "bedrock_failover" {
  source      = "../../modules/bedrock-failover"
  project     = var.project
  environment = var.environment
}
