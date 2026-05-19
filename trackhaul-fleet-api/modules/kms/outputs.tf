output "key_arn" {
  description = "ARN of the DynamoDB CMK"
  value       = aws_kms_key.dynamodb.arn
}

output "key_id" {
  description = "ID of the DynamoDB CMK"
  value       = aws_kms_key.dynamodb.key_id
}
