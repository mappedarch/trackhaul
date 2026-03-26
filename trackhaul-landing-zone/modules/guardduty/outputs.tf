# modules/guardduty/outputs.tf

output "guardduty_detector_id" {
  description = "GuardDuty detector ID in Management account"
  value       = aws_guardduty_detector.management.id
}

output "guardduty_admin_account_id" {
  description = "GuardDuty delegated admin account ID"
  value       = aws_guardduty_organization_admin_account.this.admin_account_id
}