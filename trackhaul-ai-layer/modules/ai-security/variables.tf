variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "account_id" {
  type = string
}

variable "vehicles_table_kms_key_arn" {
  description = "KMS key ARN for the trackhaul-vehicles-dev table — owned by trackhaul-fleet-api"
  type        = string
  default     = ""
}

