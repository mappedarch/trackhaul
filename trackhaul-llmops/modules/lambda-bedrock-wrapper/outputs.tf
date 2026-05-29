output "function_arn" {
  description = "ARN of the Bedrock wrapper Lambda function"
  value       = aws_lambda_function.wrapper.arn
}

output "function_name" {
  description = "Name of the Bedrock wrapper Lambda function"
  value       = aws_lambda_function.wrapper.function_name
}

output "iam_role_arn" {
  description = "IAM execution role ARN — used for cross-module policy attachments"
  value       = aws_iam_role.wrapper.arn
}