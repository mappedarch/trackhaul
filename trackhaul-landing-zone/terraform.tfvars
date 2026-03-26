# terraform.tfvars
# Real values for this deployment.
# This file is gitignored — never committed to GitHub.

aws_region     = "eu-central-1"
aws_region_dr  = "eu-west-1"

management_account_id  = "258335483092"
security_account_id    = "893946677478"
log_archive_account_id = "FILL_IN_WHEN_CREATED"
dev_account_id         = "FILL_IN_WHEN_CREATED"
prod_account_id        = "FILL_IN_WHEN_CREATED"

org_id = "o-dfdwqqufm6"

management_email  = "awsnit11@gmail.com"
security_email    = "awsnit11+sec@gmail.com"
log_archive_email = "awsnit11+logarchive@gmail.com"
dev_email         = "awsnit11+dev@gmail.com"
prod_email        = "awsnit11+prod@gmail.com"