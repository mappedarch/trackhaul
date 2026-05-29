output "feedback_table_name" {
  description = "DynamoDB feedback table name"
  value       = aws_dynamodb_table.feedback.name
}

output "feedback_table_arn" {
  description = "DynamoDB feedback table ARN"
  value       = aws_dynamodb_table.feedback.arn
}

output "feedback_capture_function_name" {
  description = "Feedback capture Lambda function name"
  value       = aws_lambda_function.feedback_capture.function_name
}

output "feedback_capture_function_arn" {
  description = "Feedback capture Lambda function ARN"
  value       = aws_lambda_function.feedback_capture.arn
}

output "feedback_reingest_function_name" {
  description = "Feedback reingestion Lambda function name"
  value       = aws_lambda_function.feedback_reingest.function_name
}

output "feedback_reingest_function_arn" {
  description = "Feedback reingestion Lambda function ARN"
  value       = aws_lambda_function.feedback_reingest.arn
}
