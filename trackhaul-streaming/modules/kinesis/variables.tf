variable "stream_name" {
  description = "Name of the Kinesis Data Stream"
  type        = string
}

variable "shard_count" {
  description = "Number of shards"
  type        = number
  default     = 4
}

variable "retention_period_hours" {
  description = "Record retention in hours (24-8760)"
  type        = number
  default     = 168 # 7 days
}

variable "kms_key_arn" {
  description = "KMS key ARN for server-side encryption"
  type        = string
}

variable "environment" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}