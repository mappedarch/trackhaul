variable "function_name" {
  description = "Lambda function name"
  type        = string
}

variable "handler" {
  description = "Handler in format filename.function_name"
  type        = string
}

variable "source_dir" {
  description = "Path to Lambda source code directory"
  type        = string
}

variable "environment" {
  description = "Environment tag value"
  type        = string
}

variable "memory_size" {
  description = "Lambda memory in MB"
  type        = number
  default     = 256
}

variable "timeout" {
  description = "Lambda timeout in seconds — must be under API Gateway 29s limit"
  type        = number
  default     = 10
}

variable "api_gateway_execution_arn" {
  description = "API Gateway execution ARN — used to scope Lambda invoke permission"
  type        = string
}

variable "stage_name" {
  description = "API Gateway stage name — used to scope Lambda invoke permission to specific stage"
  type        = string
}

variable "environment_variables" {
  description = "Environment variables passed to the function"
  type        = map(string)
  default     = {}
}

variable "dynamodb_table_name" {
  description = "DynamoDB table name injected as Lambda environment variable"
  type        = string
}

variable "execution_role_arn" {
  description = "IAM execution role ARN — created in IAM module and passed in"
  type        = string
}

variable "kms_key_arn" {
  description = "CMK ARN for Lambda environment variable encryption"
  type        = string
}
