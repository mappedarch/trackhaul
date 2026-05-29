variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "aws_region" {
  description = "Primary AWS region"
  type        = string
}

variable "prompt_path_root" {
  description = "Root path for SSM prompt parameters"
  type        = string
  default     = "/trackhaul/prompts"
}

variable "extension_layer_arn" {
  description = "ARN of the AWS Parameters and Secrets Lambda Extension layer"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS CMK ARN for LLMOps resources"
  type        = string
  default     = ""
}

variable "simulation_mode" {
  description = "When true, skips Bedrock call — used for dev and testing"
  type        = bool
  default     = false
}