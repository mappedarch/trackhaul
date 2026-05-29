variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "aws_region" {
  description = "Primary AWS region"
  type        = string
}

variable "bedrock_region" {
  description = "AWS region for Bedrock inference — must be EU"
  type        = string
  default     = "eu-central-1"
}

variable "bedrock_model_id" {
  description = "Bedrock model ID for anomaly explanation"
  type        = string
  default     = "eu.anthropic.claude-sonnet-4-5-20250929-v1:0"
}

variable "event_bus_name" {
  description = "Name of the EventBridge bus publishing anomaly events"
  type        = string
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds — must accommodate Bedrock latency"
  type        = number
  default     = 30
}

variable "lambda_memory_mb" {
  description = "Lambda memory in MB"
  type        = number
  default     = 256
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "aws_account_id" {
  description = "AWS account ID for IAM and resource policies"
  type        = string
}
