# modules/iam-identity-center/variables.tf

variable "sso_instance_arn" {
  description = "ARN of the IAM Identity Center instance"
  type        = string
}

variable "identity_store_id" {
  description = "Identity Store ID"
  type        = string
}

variable "management_account_id" {
  description = "Management account ID"
  type        = string
}

variable "security_account_id" {
  description = "Security account ID"
  type        = string
}

variable "log_archive_account_id" {
  description = "Log Archive account ID"
  type        = string
}

variable "dev_account_id" {
  description = "Dev account ID"
  type        = string
}

variable "prod_account_id" {
  description = "Prod account ID"
  type        = string
}