variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for Lambda environment variable encryption"
  type        = string
}

# SQS queue ARNs passed in from the SQS module outputs
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

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
}

variable "batch_size" {
  description = "SQS batch size per Lambda invocation"
  type        = number
  default     = 10
}

variable "state_machine_arn" {
  description = "ARN of the Step Functions state machine for incident orchestration"
  type        = string
}