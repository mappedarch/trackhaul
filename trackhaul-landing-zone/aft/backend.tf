terraform {
  backend "s3" {
    bucket         = "trackhaul-terraform-state-258335483093"
    key            = "aft/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "trackhaul-terraform-locks"
    encrypt        = true
  }
}