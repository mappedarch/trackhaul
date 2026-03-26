# modules/securityhub/main.tf
# Security Hub — aggregated security and compliance dashboard
# Delegated admin to Security account
# CIS and AWS Foundational standards enabled

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.0"
      configuration_aliases = [aws.security]
    }
  }
}

# -------------------------------------------------------
# ENABLE SECURITY HUB IN MANAGEMENT ACCOUNT
# Must be enabled before delegation
# -------------------------------------------------------
resource "aws_securityhub_account" "management" {
  enable_default_standards = false
}

# -------------------------------------------------------
# DELEGATE ADMIN TO SECURITY ACCOUNT
# Same pattern as GuardDuty
# -------------------------------------------------------
resource "aws_securityhub_organization_admin_account" "this" {
  admin_account_id = var.security_account_id

  depends_on = [aws_securityhub_account.management]
}

# -------------------------------------------------------
# ENABLE SECURITY HUB IN SECURITY ACCOUNT
# Must be enabled in Security account too
# Uses security provider
# -------------------------------------------------------
resource "aws_securityhub_account" "security" {
  provider                 = aws.security
  enable_default_standards = false

  depends_on = [aws_securityhub_organization_admin_account.this]
}

# -------------------------------------------------------
# ORGANIZATION CONFIGURATION
# Auto-enables Security Hub in all accounts
# Must run from Security account
# -------------------------------------------------------
resource "aws_securityhub_organization_configuration" "this" {
  auto_enable            = true
  auto_enable_standards  = "NONE"
  provider               = aws.security

  depends_on = [aws_securityhub_account.security]
}

# -------------------------------------------------------
# ENABLE CIS BENCHMARK STANDARD
# Runs CIS AWS Foundations checks across all accounts
# -------------------------------------------------------
resource "aws_securityhub_standards_subscription" "cis" {
  provider      = aws.security
  standards_arn = "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.2.0"

  depends_on = [aws_securityhub_account.security]
}

# -------------------------------------------------------
# ENABLE AWS FOUNDATIONAL SECURITY BEST PRACTICES
# -------------------------------------------------------
resource "aws_securityhub_standards_subscription" "aws_foundational" {
  provider      = aws.security
  standards_arn = "arn:aws:securityhub:eu-central-1::standards/aws-foundational-security-best-practices/v/1.0.0"

  depends_on = [aws_securityhub_account.security]
}