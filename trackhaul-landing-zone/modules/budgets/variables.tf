# modules/budgets/variables.tf

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

variable "alert_email" {
  description = "Email address for budget alerts"
  type        = string
}