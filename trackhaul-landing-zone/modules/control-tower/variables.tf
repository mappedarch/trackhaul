variable "landing_zone_version" {
  description = "CT landing zone version"
  type        = string
  default     = "4.0"
}

variable "governed_regions" {
  description = "AWS regions under CT governance"
  type        = list(string)
  default     = ["eu-central-1", "eu-west-1"]
}

variable "security_ou_name" {
  description = "Name of the Security OU in CT"
  type        = string
  default     = "Security"
}

variable "sandbox_ou_name" {
  description = "Name of the Sandbox OU in CT — CT requires this even if unused"
  type        = string
  default     = "Workloads"
}

variable "log_archive_account_id" {
  description = "Account ID for centralized log storage"
  type        = string
}

variable "security_account_id" {
  description = "Account ID for security tooling"
  type        = string
}

variable "logging_retention_days" {
  description = "Retention days for CT CloudTrail logs"
  type        = number
  default     = 365
}

variable "access_logging_retention_days" {
  description = "Retention days for CT S3 access logs"
  type        = number
  default     = 90
}
