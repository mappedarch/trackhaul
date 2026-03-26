# modules/config/variables.tf

variable "management_account_id" {
  description = "Management account ID"
  type        = string
}

variable "primary_region" {
  description = "Primary AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "dr_region" {
  description = "DR AWS region"
  type        = string
  default     = "eu-west-1"
}