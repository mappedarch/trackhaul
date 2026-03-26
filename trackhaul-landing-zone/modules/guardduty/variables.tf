variable "security_account_id" {
  description = "Security account ID — GuardDuty delegated admin"
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