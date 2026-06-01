# variables.tf

variable "aws_region" {
  description = "Primary AWS region — must be EU for GDPR compliance"
  type        = string
  default     = "eu-central-1"
}

variable "aws_region_dr" {
  description = "DR AWS region — must be EU for GDPR compliance"
  type        = string
  default     = "eu-west-1"
}

variable "management_account_id" {
  description = "AWS Account ID for Management account"
  type        = string
}

variable "security_account_id" {
  description = "AWS Account ID for Security account"
  type        = string
}

variable "log_archive_account_id" {
  description = "AWS Account ID for Log Archive account"
  type        = string
}

variable "dev_account_id" {
  description = "AWS Account ID for Dev account"
  type        = string
}

variable "prod_account_id" {
  description = "AWS Account ID for Prod account"
  type        = string
}

variable "org_id" {
  description = "AWS Organizations ID"
  type        = string
}

variable "security_email" {
  description = "Email for Security account"
  type        = string
}

variable "log_archive_email" {
  description = "Email for Log Archive account"
  type        = string
}

variable "dev_email" {
  description = "Email for Dev account"
  type        = string
}

variable "prod_email" {
  description = "Email for Prod account"
  type        = string
}

variable "alert_email" {
  description = "Email for budget and security alerts"
  type        = string
}
