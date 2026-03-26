# main.tf
# Root module — orchestrates all child modules.
# Think of this as the project manager delegating to specialists.

module "organizations" {
  source = "./modules/organizations"

  management_email  = var.management_email
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

module "iam_identity_center" {
  source = "./modules/iam-identity-center"

  sso_instance_arn       = var.sso_instance_arn
  identity_store_id      = var.identity_store_id
  management_account_id  = var.management_account_id
  security_account_id    = var.security_account_id
  log_archive_account_id = var.log_archive_account_id
  dev_account_id         = var.dev_account_id
  prod_account_id        = var.prod_account_id
}