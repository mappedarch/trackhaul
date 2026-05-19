terraform {
  backend "s3" {
    bucket         = "trackhaul-terraform-state-281136219737"
    key            = "trackhaul-fleet-api/dev/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "trackhaul-terraform-locks"
    encrypt        = true
  }
}