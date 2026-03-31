# modules/organizations/main.tf
# This module manages the AWS Organization structure.
# It creates OUs and member accounts.
# The Organization itself already exists — we just import it.

# -------------------------------------------------------
# FETCH EXISTING ORGANIZATION
# We use a data source to read the existing Organization.
# Data sources READ existing resources — they do not create.
# -------------------------------------------------------
data "aws_organizations_organization" "this" {}

# -------------------------------------------------------
# FETCH ROOT
# Every Organization has one Root. We need its ID to
# attach OUs and SCPs to it.
# -------------------------------------------------------
data "aws_organizations_organizational_units" "root" {
  parent_id = data.aws_organizations_organization.this.roots[0].id
}

# -------------------------------------------------------
# CREATE ORGANIZATIONAL UNITS
# Three OUs — Security, Infrastructure, Workloads
# -------------------------------------------------------
resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = data.aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_organizational_unit" "infrastructure" {
  name      = "Infrastructure"
  parent_id = data.aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_organizational_unit" "workloads" {
  name      = "Workloads"
  parent_id = data.aws_organizations_organization.this.roots[0].id
}

# -------------------------------------------------------
# CREATE MISSING ACCOUNTS
# Log Archive, Dev, Prod do not exist yet.
# Terraform will create them via Organizations API.
# NOTE: Account creation can take 2-5 minutes per account.
# -------------------------------------------------------
resource "aws_organizations_account" "log_archive" {
  name      = "trackhaul-log-archive"
  email     = var.log_archive_email
  #parent_id = aws_organizations_organizational_unit.infrastructure.id
  # changing this to match the required changes for phase 2 - moving the log archive 
  # to security OU
  parent_id = aws_organizations_organizational_unit.security.id

  tags = {
    AccountType = "Log-Archive"
    GDPR        = "true"
  }

  # This prevents Terraform from destroying the account
  # if you accidentally run terraform destroy.
  # Destroying an AWS account is irreversible.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_organizations_account" "dev" {
  name      = "trackhaul-dev"
  email     = var.dev_email
  parent_id = aws_organizations_organizational_unit.workloads.id

  tags = {
    AccountType = "Dev"
    GDPR        = "true"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_organizations_account" "prod" {
  name      = "trackhaul-prod"
  email     = var.prod_email
  parent_id = aws_organizations_organizational_unit.workloads.id

  tags = {
    AccountType = "Prod"
    GDPR        = "true"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# -------------------------------------------------------
# MOVE EXISTING ACCOUNTS INTO CORRECT OUs
# Management and Security accounts already exist.
# We move them into the right OUs.
# -------------------------------------------------------
resource "aws_organizations_account" "management" {
  name      = "trackhaul-management"
  email     = var.management_email
  parent_id = aws_organizations_organizational_unit.management.id  # ← changed

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [name, email]
  }
}

resource "aws_organizations_account" "security" {
  name      = "trackhaul-security"
  email     = var.security_email
  parent_id = aws_organizations_organizational_unit.security.id

  lifecycle {
    prevent_destroy = true
    ignore_changes = [name, email]
  }
}

resource "aws_organizations_organizational_unit" "management" {
  name      = "Management"
  parent_id = data.aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_organizational_unit" "suspended" {
  name      = "suspended"
  parent_id = data.aws_organizations_organization.this.roots[0].id
}