output "guardrail_id" {
  value       = aws_bedrock_guardrail.fleet_assistant.guardrail_id
  description = "Guardrail ID for Lambda invoke calls"
}

output "guardrail_version" {
  value       = aws_bedrock_guardrail_version.fleet_assistant.version
  description = "Published guardrail version"
}

output "guardrail_arn" {
  value       = aws_bedrock_guardrail.fleet_assistant.guardrail_arn
  description = "Guardrail ARN for IAM policies"
}