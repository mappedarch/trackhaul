variable "alias_name" {
  description = "KMS key alias — do not include alias/ prefix"
  type        = string
}

variable "description" {
  type = string
}

variable "deletion_window_in_days" {
  type    = number
  default = 30 # Production: 30 days. Never 7 in prod — too easy to trigger accidentally.
}

variable "allowed_service_principal" {
  description = "AWS service principal allowed to use this key (e.g. kinesis.amazonaws.com)"
  type        = string
}

variable "allowed_iam_arns" {
  description = "IAM role ARNs permitted to use the key for encrypt/decrypt"
  type        = list(string)
  default     = []
}

variable "aws_account_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}