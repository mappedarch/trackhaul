# backend.tf
# This file tells Terraform where to store its state file.
# State file = Terraform's database of everything it has created.
# We store it in S3 (durable) with DynamoDB locking (safe concurrent access).

terraform {
  backend "s3" {
    bucket         = "trackhaul-terraform-state-258335483093"
    key            = "phase1/landing-zone/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "trackhaul-terraform-locks"
    encrypt        = true
  }
}