terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.primary_region
}

module "control_tower_account_factory" {
  source  = "aws-ia/control_tower_account_factory/aws"
  version = "1.18.1"

  ct_home_region              = var.primary_region
  ct_management_account_id    = var.management_account_id
  log_archive_account_id      = var.log_archive_account_id
  audit_account_id            = var.security_account_id
  aft_management_account_id   = var.aft_account_id

  vcs_provider = "codecommit"

  aft_feature_cloudtrail_data_events      = false
  aft_feature_enterprise_support          = false
  aft_feature_delete_default_vpcs_enabled = true

  terraform_version      = "1.14.3"
  terraform_distribution = "oss"
}