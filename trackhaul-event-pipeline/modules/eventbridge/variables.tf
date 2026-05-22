variable "project" {
  description = "Project name prefix for all resources"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "enable_archive" {
  description = "Whether to enable event archive on the custom bus"
  type        = bool
  default     = true
}

variable "archive_retention_days" {
  description = "Number of days to retain archived events"
  type        = number
  default     = 90
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------
# SQS target ARNs — one per consumer
# Used by EventBridge rules to route events to the correct queue
# ---------------------------------------------------------------
variable "geofence_queue_arn" {
  description = "ARN of the geofence SQS queue"
  type        = string
}

variable "fuel_anomaly_queue_arn" {
  description = "ARN of the fuel anomaly SQS queue"
  type        = string
}

variable "driver_scoring_queue_arn" {
  description = "ARN of the driver scoring SQS queue"
  type        = string
}

variable "maintenance_queue_arn" {
  description = "ARN of the maintenance SQS queue"
  type        = string
}