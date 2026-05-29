output "prompt_version_arn" {
  description = "ARN of the versioned prompt parameter"
  value       = aws_ssm_parameter.prompt_version.arn
}

output "prompt_active_pointer_arn" {
  description = "ARN of the active pointer parameter"
  value       = aws_ssm_parameter.prompt_active_pointer.arn
}

output "prompt_version_name" {
  description = "SSM path of the versioned prompt — used in Lambda IAM policy"
  value       = aws_ssm_parameter.prompt_version.name
}

output "prompt_active_pointer_name" {
  description = "SSM path of the active pointer — used in Lambda IAM policy"
  value       = aws_ssm_parameter.prompt_active_pointer.name
}