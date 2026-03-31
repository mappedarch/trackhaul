output "chaos_findings_summary" {
  description = "Summary of intentional misconfigurations — inputs to the governance remediation plan"
  value = {
    finding_1_iam_user_with_key    = "IAM user '${aws_iam_user.dev_admin.name}' has active long-lived access key — no MFA, no rotation"
    finding_2_ci_admin_access      = "CI user '${aws_iam_user.ci_deploy.name}' has AdministratorAccess — violates least privilege"
    finding_3_s3_blocked_by_scp    = "S3 bucket creation blocked by Phase 1 GDPR SCP — guardrails already working before CT enrollment"
    finding_4_open_security_group  = "Security group '${aws_security_group.wide_open_ssh.name}' — port 22 and 3389 open to 0.0.0.0/0"
    finding_5_no_cloudtrail        = "No CloudTrail in dev account — zero audit trail, GDPR Article 30 violation"
    remediation_approach           = "Enroll into Control Tower — SCPs will prevent IAM user creation, Config rules will flag open SGs, CT mandatory CloudTrail will activate"
  }
}

output "iam_user_dev_admin_arn" {
  description = "ARN of the chaos IAM user — used in audit evidence"
  value       = aws_iam_user.dev_admin.arn
}

output "ci_deploy_user_arn" {
  description = "ARN of the CI deploy user — used in audit evidence"
  value       = aws_iam_user.ci_deploy.arn
}

/*
output "temp_bucket_arn" {
  description = "ARN of the unencrypted temp bucket — used in audit evidence"
  value       = aws_s3_bucket.temp_data.arn
}
*/

output "open_sg_id" {
  description = "ID of the wide-open SSH security group"
  value       = aws_security_group.wide_open_ssh.id
}

output "access_key_id" {
  description = "Access key ID (not secret) — shows key exists in audit"
  value       = aws_iam_access_key.dev_admin_key.id
  sensitive   = false
}
