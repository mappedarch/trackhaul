output "table_name" {
  description = "Token tracker DynamoDB table name"
  value       = aws_dynamodb_table.token_tracker.name
}

output "table_arn" {
  description = "Token tracker DynamoDB table ARN"
  value       = aws_dynamodb_table.token_tracker.arn
}
