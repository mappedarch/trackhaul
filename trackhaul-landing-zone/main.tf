# main.tf
# Root module — orchestrates all child modules.

module "organizations" {
  source = "./modules/organizations"

  security_email    = var.security_email
  log_archive_email = var.log_archive_email
  dev_email         = var.dev_email
  prod_email        = var.prod_email
}

module "scp" {
  source = "./modules/scp"

  security_ou_id       = module.organizations.security_ou_id
  infrastructure_ou_id = module.organizations.infrastructure_ou_id
  workloads_ou_id      = module.organizations.workloads_ou_id
}

module "cloudtrail" {
  source = "./modules/cloudtrail"

  management_account_id  = var.management_account_id
  log_archive_account_id = var.log_archive_account_id
  org_id                 = var.org_id
}

module "config" {
  source = "./modules/config"

  management_account_id = var.management_account_id
  primary_region        = var.aws_region
  dr_region             = var.aws_region_dr
}

module "guardduty" {
  source = "./modules/guardduty"

  security_account_id    = var.security_account_id
  log_archive_account_id = var.log_archive_account_id
  dev_account_id         = var.dev_account_id
  prod_account_id        = var.prod_account_id

  providers = {
    aws.security = aws.security
  }
}