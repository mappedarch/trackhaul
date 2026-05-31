variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "lambda_src_path" {
  description = "Path to the Lambda source zip file"
  type        = string
}

variable "lambda_reserved_concurrency" {
  description = "Maximum simultaneous agent runs. Controls Bedrock call rate."
  type        = number
  default     = 5
}

variable "sqs_visibility_timeout_seconds" {
  description = "Must be greater than Lambda timeout. Agent runs can take 30s."
  type        = number
  default     = 120
}

variable "sqs_message_retention_seconds" {
  description = "How long unprocessed incidents stay in queue before expiry"
  type        = number
  default     = 86400 # 24 hours
}

variable "dlq_message_retention_seconds" {
  description = "How long failed incidents stay in DLQ for investigation"
  type        = number
  default     = 604800 # 7 days
}

variable "lambda_timeout_seconds" {
  description = "Lambda timeout. Agent graph can take 15-30s per invocation."
  type        = number
  default     = 60
}

variable "kms_key_arn" {
  description = "KMS key ARN for SQS and Lambda encryption"
  type        = string
}

variable "guardrail_id" {
  type        = string
  description = "Bedrock Guardrail ID attached to all LLM calls"
}

variable "guardrail_version" {
  type        = string
  description = "Pinned guardrail version — never use DRAFT in production"
}