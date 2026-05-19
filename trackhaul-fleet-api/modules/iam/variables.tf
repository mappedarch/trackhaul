variable "function_name" {
  description = "Lambda function name — used to scope all policy resources"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "aws_region" {
  description = "AWS region — used to scope CloudWatch log group ARN"
  type        = string
}

variable "account_id" {
  description = "AWS account ID — used to scope CloudWatch log group ARN"
  type        = string
}

variable "dynamodb_table_arn" {
  description = "ARN of the DynamoDB vehicles table"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS CMK used for DynamoDB encryption"
  type        = string
}
