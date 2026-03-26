# providers.tf
# This file tells Terraform which cloud provider to use and how to connect.
# We define the AWS provider and pin its version.
# Version pinning is critical — without it Terraform may auto-upgrade
# the provider and break your code.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Default provider — connects to Management account, eu-central-1
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "TrackHaul"
      Environment = "Management"
      ManagedBy   = "Terraform"
      Owner       = "Platform-Team"
      GDPR        = "true"
    }
  }
}