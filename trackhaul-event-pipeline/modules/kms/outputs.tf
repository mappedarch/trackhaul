output "key_arn" {
  description = "ARN of the pipeline KMS key — used by SQS, SNS, Lambda, and CloudWatch Logs"
  value       = aws_kms_key.pipeline.arn
}

output "key_id" {
  description = "ID of the pipeline KMS key"
  value       = aws_kms_key.pipeline.key_id
}

output "key_alias" {
  description = "Alias of the pipeline KMS key"
  value       = aws_kms_alias.pipeline.name
}
