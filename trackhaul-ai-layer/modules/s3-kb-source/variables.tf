variable "environment" { type = string }
variable "aws_region"  { type = string }
variable "kms_key_arn" {
  description = "CMK ARN for S3 server-side encryption"
  type        = string
}