variable "project" {
  description = "Project name used in resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment — dev, prod"
  type        = string
}

variable "lambda_role_arns" {
  description = "List of Lambda execution role ARNs that need decrypt access"
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}

variable "eventbridge_role_arn" {
  description = "ARN of the EventBridge IAM role that delivers to encrypted SQS queues"
  type        = string
}