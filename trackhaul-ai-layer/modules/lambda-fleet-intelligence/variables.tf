variable "project" {}
variable "aws_region" {}
variable "lambda_role_arn" {}
variable "lambda_zip_path" {}
variable "knowledge_base_id" {}
variable "guardrail_id" {
  description = "Bedrock guardrail ID for GDPR and safety enforcement"
  type        = string
}

variable "guardrail_version" {
  description = "Bedrock guardrail version"
  type        = string
  default     = "DRAFT"
}