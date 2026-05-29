variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting DynamoDB table and Lambda"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "golden_dataset_bucket" {
  description = "S3 bucket name where golden dataset is stored"
  type        = string
}

variable "golden_dataset_prefix" {
  description = "S3 prefix for golden dataset files"
  type        = string
  default     = "golden-dataset"
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
