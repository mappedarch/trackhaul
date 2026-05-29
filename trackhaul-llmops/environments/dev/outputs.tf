output "kms_key_arn" {
  description = "ARN of the LLMOps KMS key"
  value       = aws_kms_key.llmops.arn
}

output "kms_key_alias" {
  description = "Alias of the LLMOps KMS key"
  value       = aws_kms_alias.llmops.name
}

output "prompt_version_ssm_path" {
  description = "SSM path of the active fleet assistant prompt version"
  value       = module.fleet_assistant_prompt.prompt_version_name
}

output "prompt_active_pointer_ssm_path" {
  description = "SSM path of the active pointer — reference this in Lambda"
  value       = module.fleet_assistant_prompt.prompt_active_pointer_name
}