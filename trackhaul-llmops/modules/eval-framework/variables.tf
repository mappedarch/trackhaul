variable "environment" {
  description = "Deployment environment (dev, prod)"
  type        = string
}

variable "naming_prefix" {
  description = "Naming prefix for all resources — sourced from locals, never hardcoded"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of KMS key used to encrypt bucket objects"
  type        = string
}

variable "eval_results_retention_days" {
  description = "Days before eval results transition to Glacier"
  type        = number
}
