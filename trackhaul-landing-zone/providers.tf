# providers.tf

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

provider "aws" {
  alias  = "security"
  region = var.aws_region

  assume_role {
    role_arn = "arn:aws:iam::${var.security_account_id}:role/OrganizationAccountAccessRole"
  }

  default_tags {
    tags = {
      Project     = "TrackHaul"
      Environment = "Security"
      ManagedBy   = "Terraform"
      Owner       = "Platform-Team"
      GDPR        = "true"
    }
  }
}
