output "lambda_function_arns" {
  description = "ARNs of all consumer Lambda functions"
  value       = { for k, v in aws_lambda_function.consumer : k => v.arn }
}

output "lambda_function_names" {
  description = "Names of all consumer Lambda functions"
  value       = { for k, v in aws_lambda_function.consumer : k => v.function_name }
}

output "lambda_execution_role_arns" {
  description = "Execution role ARNs"
  value       = { for k, v in aws_iam_role.lambda_exec : k => v.arn }
}

# Individual ARN outputs for Step Functions wiring
output "diagnose_lambda_arn" {
  description = "ARN of the maintenance Lambda — used as diagnose step in incident workflow"
  value       = aws_lambda_function.consumer["maintenance"].arn
}

output "maintenance_lambda_arn" {
  description = "ARN of the maintenance Lambda"
  value       = aws_lambda_function.consumer["maintenance"].arn
}

output "alert_lambda_arn" {
  description = "ARN of the fuel_anomaly Lambda — used as alert step in incident workflow"
  value       = aws_lambda_function.consumer["fuel_anomaly"].arn
}