# modules/iam-identity-center/main.tf
# IAM Identity Center — centralized SSO for all TrackHaul accounts
# Zero IAM users — all human access via SSO only
# Four permission sets: PlatformAdmin, Developer, Auditor, BreakGlass

# -------------------------------------------------------
# PERMISSION SET 1 — PLATFORM ADMIN
# Full admin on Dev, ReadOnly on Prod
# Used by platform/DevOps team for day to day operations
# -------------------------------------------------------
resource "aws_ssoadmin_permission_set" "platform_admin" {
  name             = "PlatformAdmin"
  description      = "Full admin on Dev. ReadOnly on Prod. For platform team."
  instance_arn     = var.sso_instance_arn
  session_duration = "PT8H"

  tags = {
    Role    = "PlatformAdmin"
    Project = "TrackHaul"
  }
}

# Attach AWS managed AdministratorAccess policy
resource "aws_ssoadmin_managed_policy_attachment" "platform_admin" {
  instance_arn       = var.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.platform_admin.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# -------------------------------------------------------
# PERMISSION SET 2 — DEVELOPER
# Limited write access on Dev only
# ReadOnly on Prod
# -------------------------------------------------------
resource "aws_ssoadmin_permission_set" "developer" {
  name             = "Developer"
  description      = "Limited write on Dev. ReadOnly on Prod. For developers."
  instance_arn     = var.sso_instance_arn
  session_duration = "PT8H"

  tags = {
    Role    = "Developer"
    Project = "TrackHaul"
  }
}

# Attach PowerUserAccess — full access except IAM and Organizations
resource "aws_ssoadmin_managed_policy_attachment" "developer" {
  instance_arn       = var.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.developer.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# -------------------------------------------------------
# PERMISSION SET 3 — AUDITOR
# ReadOnly on all accounts
# Used by compliance and security team
# -------------------------------------------------------
resource "aws_ssoadmin_permission_set" "auditor" {
  name             = "Auditor"
  description      = "ReadOnly on all accounts. For compliance and security team."
  instance_arn     = var.sso_instance_arn
  session_duration = "PT8H"

  tags = {
    Role    = "Auditor"
    Project = "TrackHaul"
  }
}

resource "aws_ssoadmin_managed_policy_attachment" "auditor" {
  instance_arn       = var.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.auditor.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# -------------------------------------------------------
# PERMISSION SET 4 — BREAK GLASS
# Emergency admin access to Prod
# 1 hour session only
# MFA required — enforced via inline policy condition
# Triggers alarms when used
# -------------------------------------------------------
resource "aws_ssoadmin_permission_set" "break_glass" {
  name             = "BreakGlass"
  description      = "Emergency Prod admin. 1hr session. MFA required. Alarms triggered on use."
  instance_arn     = var.sso_instance_arn
  session_duration = "PT1H"

  tags = {
    Role    = "BreakGlass"
    Project = "TrackHaul"
  }
}

resource "aws_ssoadmin_managed_policy_attachment" "break_glass" {
  instance_arn       = var.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.break_glass.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Inline policy — deny all actions if MFA not present
resource "aws_ssoadmin_permission_set_inline_policy" "break_glass_mfa" {
  instance_arn       = var.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.break_glass.arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyWithoutMFA"
        Effect = "Deny"
        Action = "*"
        Resource = "*"
        Condition = {
          BoolIfExists = {
            "aws:MultiFactorAuthPresent" = "false"
          }
        }
      }
    ]
  })
}

# -------------------------------------------------------
# GROUPS
# We assign permission sets to groups not individual users
# Users are added to groups — groups get account assignments
# This is how enterprise IAM is managed at scale
# -------------------------------------------------------
resource "aws_identitystore_group" "platform_admins" {
  identity_store_id = var.identity_store_id
  display_name      = "trackhaul-platform-admins"
  description       = "Platform and DevOps team"
}

resource "aws_identitystore_group" "developers" {
  identity_store_id = var.identity_store_id
  display_name      = "trackhaul-developers"
  description       = "Application developers"
}

resource "aws_identitystore_group" "auditors" {
  identity_store_id = var.identity_store_id
  display_name      = "trackhaul-auditors"
  description       = "Compliance and security auditors"
}

resource "aws_identitystore_group" "break_glass" {
  identity_store_id = var.identity_store_id
  display_name      = "trackhaul-break-glass"
  description       = "Emergency access group — minimal members"
}

# -------------------------------------------------------
# ACCOUNT ASSIGNMENTS
# Wire groups to permission sets to accounts
# PlatformAdmin → Admin on Dev, ReadOnly on Prod
# Developer → PowerUser on Dev, ReadOnly on Prod
# Auditor → ReadOnly on all accounts
# BreakGlass → Admin on Prod only
# -------------------------------------------------------

# Platform Admin — Dev (full admin)
resource "aws_ssoadmin_account_assignment" "platform_admin_dev" {
  instance_arn       = var.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.platform_admin.arn
  principal_id       = aws_identitystore_group.platform_admins.group_id
  principal_type     = "GROUP"
  target_id          = var.dev_account_id
  target_type        = "AWS_ACCOUNT"
}

# Platform Admin — Prod (readonly)
resource "aws_ssoadmin_account_assignment" "platform_admin_prod" {
  instance_arn       = var.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.auditor.arn
  principal_id       = aws_identitystore_group.platform_admins.group_id
  principal_type     = "GROUP"
  target_id          = var.prod_account_id
  target_type        = "AWS_ACCOUNT"
}

# Developer — Dev (power user)
resource "aws_ssoadmin_account_assignment" "developer_dev" {
  instance_arn       = var.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.developer.arn
  principal_id       = aws_identitystore_group.developers.group_id
  principal_type     = "GROUP"
  target_id          = var.dev_account_id
  target_type        = "AWS_ACCOUNT"
}

# Developer — Prod (readonly)
resource "aws_ssoadmin_account_assignment" "developer_prod" {
  instance_arn       = var.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.auditor.arn
  principal_id       = aws_identitystore_group.developers.group_id
  principal_type     = "GROUP"
  target_id          = var.prod_account_id
  target_type        = "AWS_ACCOUNT"
}

# Auditor — all accounts
resource "aws_ssoadmin_account_assignment" "auditor_management" {
  instance_arn       = var.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.auditor.arn
  principal_id       = aws_identitystore_group.auditors.group_id
  principal_type     = "GROUP"
  target_id          = var.management_account_id
  target_type        = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "auditor_security" {
  instance_arn       = var.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.auditor.arn
  principal_id       = aws_identitystore_group.auditors.group_id
  principal_type     = "GROUP"
  target_id          = var.security_account_id
  target_type        = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "auditor_log_archive" {
  instance_arn       = var.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.auditor.arn
  principal_id       = aws_identitystore_group.auditors.group_id
  principal_type     = "GROUP"
  target_id          = var.log_archive_account_id
  target_type        = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "auditor_dev" {
  instance_arn       = var.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.auditor.arn
  principal_id       = aws_identitystore_group.auditors.group_id
  principal_type     = "GROUP"
  target_id          = var.dev_account_id
  target_type        = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "auditor_prod" {
  instance_arn       = var.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.auditor.arn
  principal_id       = aws_identitystore_group.auditors.group_id
  principal_type     = "GROUP"
  target_id          = var.prod_account_id
  target_type        = "AWS_ACCOUNT"
}

# BreakGlass — Prod only
resource "aws_ssoadmin_account_assignment" "break_glass_prod" {
  instance_arn       = var.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.break_glass.arn
  principal_id       = aws_identitystore_group.break_glass.group_id
  principal_type     = "GROUP"
  target_id          = var.prod_account_id
  target_type        = "AWS_ACCOUNT"
}