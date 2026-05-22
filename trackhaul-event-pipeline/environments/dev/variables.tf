variable "project" {
  type    = string
  default = "trackhaul"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "aws_region" {
  type    = string
  default = "eu-central-1"
}
variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "ops_email" {
  description = "Email address for operational alerts"
  type        = string
}
