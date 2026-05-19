variable "aws_region" {
  description = "Primary AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "trackhaul"
}

variable "account_id" {
  description = "AWS account ID — used to scope IAM and KMS policies"
  type        = string
}