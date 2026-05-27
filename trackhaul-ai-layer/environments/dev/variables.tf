variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "account_id" {
  type    = string
}

variable "pinecone_api_key" {
  type      = string
  sensitive = true
}