variable "stream_arn" {
  description = "ARN of the Kinesis Data Stream to consume"
  type        = string
}

variable "stream_name" {
  description = "Name of the Kinesis Data Stream"
  type        = string
}

variable "lambda_zip_path" {
  description = "Path to the Lambda deployment package"
  type        = string
}

variable "anomaly_event_bus_name" {
  description = "EventBridge custom bus name for anomaly events"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for Lambda environment variable encryption"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}