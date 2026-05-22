# modules/organizations/outputs.tf

output "root_id" {
  description = "Organization Root ID"
  value       = data.aws_organizations_organization.this.roots[0].id
}

output "org_id" {
  description = "Organization ID"
  value       = data.aws_organizations_organization.this.id
}

output "security_ou_id" {
  description = "Security OU ID"
  value       = aws_organizations_organizational_unit.security.id
}

output "infrastructure_ou_id" {
  description = "Infrastructure OU ID"
  value       = aws_organizations_organizational_unit.infrastructure.id
}

output "workloads_ou_id" {
  description = "Workloads OU ID"
  value       = aws_organizations_organizational_unit.workloads.id
}

output "dev_ou_id" {
  description = "Dev OU ID"
  value       = aws_organizations_organizational_unit.dev.id
}

output "prod_ou_id" {
  description = "Prod OU ID"
  value       = aws_organizations_organizational_unit.prod.id
}

output "security_account_id" {
  description = "Security account ID"
  value       = aws_organizations_account.security.id
}

output "log_archive_account_id" {
  description = "Log Archive account ID"
  value       = aws_organizations_account.log_archive.id
}

output "dev_account_id" {
  description = "Dev account ID"
  value       = aws_organizations_account.dev.id
}

output "prod_account_id" {
  description = "Prod account ID"
  value       = aws_organizations_account.prod.id
}