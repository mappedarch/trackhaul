output "aiops_explainer_function_name" {
  description = "AIOps explainer Lambda function name"
  value       = module.aiops_explainer.lambda_function_name
}

output "aiops_explainer_function_arn" {
  description = "AIOps explainer Lambda function ARN"
  value       = module.aiops_explainer.lambda_function_arn
}

output "explanation_log_group" {
  description = "CloudWatch log group for AIOps explanations"
  value       = module.aiops_explainer.log_group_name
}
