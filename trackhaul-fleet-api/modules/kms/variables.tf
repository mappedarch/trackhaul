variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "account_id" {
  description = "AWS account ID — required for KMS key policy root principal"
  type        = string
}

variable "lambda_exec_role_arn" {
  description = "ARN of the Lambda execution role that needs KMS decrypt access"
  type        = string
}
