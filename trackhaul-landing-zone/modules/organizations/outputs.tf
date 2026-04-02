# modules/organizations/outputs.tf
# These values are exported after apply.
# Other modules will use these — for example the SCP module
# needs the OU IDs to attach policies to them.

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

output "management_ou_id" {
  description = "Management OU ID"
  value       = aws_organizations_organizational_unit.management.id
}

output "aft_ou_id" {
  description = "ID of the AFT OU"
  value       = aws_organizations_organizational_unit.aft.id
}

output "aft_account_id" {
  description = "Account ID of the AFT account"
  value       = aws_organizations_account.aft.id
}