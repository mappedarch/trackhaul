variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "aws_account_id" {
  type = string
}

variable "shard_count" {
  type    = number
  default = 4
}

variable "retention_period_hours" {
  type    = number
  default = 168
}