# modules/cloudtrail/variables.tf

variable "log_archive_account_id" {
  description = "Log Archive account ID — where CloudTrail logs are stored"
  type        = string
}

variable "management_account_id" {
  description = "Management account ID"
  type        = string
}

variable "org_id" {
  description = "AWS Organization ID"
  type        = string
}