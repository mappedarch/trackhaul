# modules/scp/outputs.tf

output "governance_policy_id" {
  description = "ID of the governance SCP"
  value       = aws_organizations_policy.governance.id
}

output "gdpr_data_policy_id" {
  description = "ID of the GDPR data controls SCP"
  value       = aws_organizations_policy.gdpr_data.id
}