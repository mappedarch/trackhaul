output "function_arn" {
  description = "Lambda function ARN — used by API Gateway integration"
  value       = aws_lambda_function.this.arn
}

output "invoke_arn" {
  description = "Lambda invoke ARN — this is what API Gateway integration URI needs"
  value       = aws_lambda_function.this.invoke_arn
}

output "function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.this.function_name
}