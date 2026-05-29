variable "aws_region" {
  description = "Primary AWS region"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "event_bus_name" {
  description = "EventBridge bus name from the event pipeline project"
  type        = string
}

variable "bedrock_region" {
  description = "AWS region for Bedrock inference"
  type        = string
}

variable "bedrock_model_id" {
  description = "Bedrock model ID"
  type        = string
}
