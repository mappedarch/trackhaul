variable "project" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for Step Functions encryption"
  type        = string
}

variable "aws_region" {
  description = "AWS region — used to construct Lambda ARNs"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID — used to construct Lambda ARNs"
  type        = string
}

variable "critical_alerts_topic_arn" {
  description = "ARN of the SNS topic for critical operational alerts"
  type        = string
}

variable "maintenance_alerts_topic_arn" {
  description = "ARN of the SNS topic for maintenance recommendation alerts"
  type        = string
}