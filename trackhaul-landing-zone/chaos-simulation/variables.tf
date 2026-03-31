variable "aws_region" {
  description = "AWS region to deploy chaos resources into"
  type        = string
  default     = "eu-central-1"
}

variable "account_id" {
  description = "Dev account ID — chaos resources deploy here only"
  type        = string
  default     = "386324384619"
}

variable "chaos_bucket_name" {
  description = "Name of the intentionally misconfigured S3 bucket"
  type        = string
  default     = "trackhaul-dev-data-2021-temp"
}
