# modules/organizations/variables.tf
# Input variables for the organizations module.
# Email addresses are required for account creation.
# Each AWS account must have a unique email address.

variable "management_email" {
  description = "Email address for Management account"
  type        = string
}

variable "security_email" {
  description = "Email address for Security account"
  type        = string
}

variable "log_archive_email" {
  description = "Email address for Log Archive account — must be unique"
  type        = string
}

variable "dev_email" {
  description = "Email address for Dev account — must be unique"
  type        = string
}

variable "prod_email" {
  description = "Email address for Prod account — must be unique"
  type        = string
}

variable "aft_email" {
  description = "Email address for the AFT management account"
  type        = string
}