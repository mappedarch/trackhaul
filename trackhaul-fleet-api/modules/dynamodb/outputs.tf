output "table_name" {
  description = "DynamoDB table name"
  value       = aws_dynamodb_table.vehicles.name
}

output "table_arn" {
  description = "DynamoDB table ARN — used for IAM policy scoping"
  value       = aws_dynamodb_table.vehicles.arn
}