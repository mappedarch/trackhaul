# modules/securityhub/outputs.tf

output "securityhub_admin_account_id" {
  description = "Security Hub delegated admin account ID"
  value       = aws_securityhub_organization_admin_account.this.admin_account_id
}