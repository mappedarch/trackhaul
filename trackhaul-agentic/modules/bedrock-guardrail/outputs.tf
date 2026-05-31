output "guardrail_id" {
  value       = aws_bedrock_guardrail.fleet_agent.guardrail_id
  description = "Bedrock Guardrail ID — passed to Lambda as environment variable"
}

output "guardrail_version" {
  value       = aws_bedrock_guardrail_version.fleet_agent.version
  description = "Guardrail version number — must be pinned, not DRAFT"
}