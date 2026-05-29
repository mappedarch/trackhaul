variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "prompt_name" {
  description = "Name of the prompt — used in SSM path"
  type        = string
}

variable "prompt_text" {
  description = "The actual prompt content"
  type        = string
  sensitive   = true
}

variable "prompt_version" {
  description = "Version label e.g. v1"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting SecureString parameters"
  type        = string
}

variable "prompt_path_root" {
  description = "Root path for SSM prompt parameters e.g. /trackhaul/llmops/prompts"
  type        = string
}