variable "consumer_name" {
  description = "Name of the consumer (e.g. geofence, fuel_anomaly)"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "visibility_timeout_seconds" {
  description = "Visibility timeout — set to 6x Lambda timeout"
  type        = number
  default     = 180 # Assumes 30s Lambda timeout
}

variable "message_retention_seconds" {
  description = "How long messages are retained"
  type        = number
  default     = 86400 # 1 day for dev; use 345600 (4 days) for prod
}

variable "max_receive_count" {
  description = "Retry attempts before moving to DLQ"
  type        = number
  default     = 3
}

variable "kms_key_arn" {
  description = "KMS key ARN for queue encryption"
  type        = string
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN for DLQ alarm notifications"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
