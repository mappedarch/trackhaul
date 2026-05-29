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