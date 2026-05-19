variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "project" {
  description = "Project name prefix"
  type        = string
}

variable "token_validity_hours" {
  description = "Access and ID token validity in hours"
  type        = number
  default     = 1
}

variable "refresh_token_validity_hours" {
  description = "Refresh token validity in hours — set to shift length"
  type        = number
  default     = 8
}