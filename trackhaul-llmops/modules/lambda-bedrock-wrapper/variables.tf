variable "environment" {
  description = "Deployment environment name"
  type        = string
}

variable "extension_layer_arn" {
  description = "ARN of the AWS Parameters and Secrets Lambda Extension layer"
  type        = string
}

variable "ssm_prompt_active_pointer_name" {
  description = "SSM parameter name for the active prompt pointer"
  type        = string
}

variable "ssm_prompt_active_pointer_arn" {
  description = "SSM parameter ARN for IAM policy scoping"
  type        = string
}

variable "ssm_prompt_version_arn" {
  description = "SSM parameter ARN for versioned prompts — IAM policy scoping"
  type        = string
}

variable "bedrock_model_id" {
  description = "Bedrock model ID to invoke"
  type        = string
  default     = "anthropic.claude-3-sonnet-20240229-v1:0"
}

variable "kms_key_arn" {
  description = "KMS CMK ARN for CloudWatch log group encryption"
  type        = string
}

variable "simulation_mode" {
  description = "When true, skips Bedrock call and returns a synthetic response"
  type        = bool
  default     = false
}

variable "ssm_parameter_ttl" {
  description = "TTL in seconds for the Lambda extension SSM cache"
  type        = number
  default     = 60
}