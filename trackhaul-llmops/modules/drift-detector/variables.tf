variable "environment" {
  description = "Deployment environment — dev or prod"
  type        = string
}

variable "naming_prefix" {
  description = "Resource naming prefix — e.g. trackhaul-llmops"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for SNS and CloudWatch log encryption"
  type        = string
}

variable "prompt_version" {
  description = "Active prompt version label — matches SSM path suffix e.g. active"
  type        = string
  default     = "active"
}
