variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS CMK for DynamoDB encryption"
  type        = string
}