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