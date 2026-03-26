# modules/securityhub/variables.tf

variable "security_account_id" {
  description = "Security account ID — Security Hub delegated admin"
  type        = string
}

variable "primary_region" {
  description = "Primary AWS region"
  type        = string
  default     = "eu-central-1"
}