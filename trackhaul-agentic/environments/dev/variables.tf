variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "lambda_reserved_concurrency" {
  description = "Maximum simultaneous agent runs. Controls Bedrock call rate at POC scale."
  type        = number
  default     = 5
}