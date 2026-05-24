variable "kinesis_stream_arn" {
  type = string
}

variable "kinesis_stream_name" {
  type = string
}

variable "s3_bucket_arn" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "glue_database_name" {
  type = string
}

variable "glue_table_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "environment" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "kinesis_kms_key_arn" {
  type        = string
  description = "KMS key ARN used to encrypt the Kinesis source stream"
}