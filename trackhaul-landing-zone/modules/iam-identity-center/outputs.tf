# modules/iam-identity-center/outputs.tf

output "platform_admins_group_id" {
  description = "Platform Admins group ID"
  value       = aws_identitystore_group.platform_admins.group_id
}

output "developers_group_id" {
  description = "Developers group ID"
  value       = aws_identitystore_group.developers.group_id
}

output "auditors_group_id" {
  description = "Auditors group ID"
  value       = aws_identitystore_group.auditors.group_id
}

output "break_glass_group_id" {
  description = "BreakGlass group ID"
  value       = aws_identitystore_group.break_glass.group_id
}