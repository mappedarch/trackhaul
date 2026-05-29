output "lambda_function_name" {
  description = "Name of the AIOps explainer Lambda function"
  value       = aws_lambda_function.aiops_explainer.function_name
}

output "lambda_function_arn" {
  description = "ARN of the AIOps explainer Lambda function"
  value       = aws_lambda_function.aiops_explainer.arn
}

output "log_group_name" {
  description = "CloudWatch log group for explanation outputs"
  value       = aws_cloudwatch_log_group.aiops_explainer.name
}
