# modules/organizations/main.tf
# Reads the existing AWS Organization and builds the OU structure.
# Creates all member accounts under the correct OUs.

data "aws_organizations_organization" "this" {}

# --- OU Structure ---

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

resource "aws_organizations_organizational_unit" "dev" {
  name      = "Dev"
  parent_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_organizational_unit" "prod" {
  name      = "Prod"
  parent_id = aws_organizations_organizational_unit.workloads.id
}

# --- Member Accounts ---

resource "aws_organizations_account" "security" {
  name      = "trackhaul-security"
  email     = var.security_email
  parent_id = aws_organizations_organizational_unit.security.id
}

resource "aws_organizations_account" "log_archive" {
  name      = "trackhaul-log-archive"
  email     = var.log_archive_email
  parent_id = aws_organizations_organizational_unit.security.id
}

resource "aws_organizations_account" "dev" {
  name      = "trackhaul-dev"
  email     = var.dev_email
  parent_id = aws_organizations_organizational_unit.dev.id
}

resource "aws_organizations_account" "prod" {
  name      = "trackhaul-prod"
  email     = var.prod_email
  parent_id = aws_organizations_organizational_unit.prod.id
}