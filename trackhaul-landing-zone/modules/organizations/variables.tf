# modules/organizations/variables.tf

variable "security_email" {
  description = "Email address for Security account"
  type        = string
}

variable "log_archive_email" {
  description = "Email address for Log Archive account"
  type        = string
}

variable "dev_email" {
  description = "Email address for Dev account"
  type        = string
}

variable "prod_email" {
  description = "Email address for Prod account"
  type        = string
}