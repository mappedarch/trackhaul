terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "trackhaul-terraform-state-281136219737"
    key            = "trackhaul-agentic/dev/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "trackhaul-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      project    = "trackhaul"
      component  = "agentic"
      managed_by = "terraform"
    }
  }
}