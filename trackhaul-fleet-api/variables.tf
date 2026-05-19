variable "aws_region" {
  description = "Primary AWS region — must be EU"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name used in resource naming and tagging"
  type        = string
  default     = "trackhaul-fleet-api"
}