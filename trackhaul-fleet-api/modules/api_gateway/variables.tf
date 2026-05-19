variable "api_name" {
  description = "Name of the REST API"
  type        = string
}

variable "stage_name" {
  description = "Deployment stage name (dev, prod)"
  type        = string
}

variable "environment" {
  description = "Environment tag value"
  type        = string
}

variable "throttling_rate_limit" {
  description = "Requests per second at stage level"
  type        = number
  default     = 100
}

variable "throttling_burst_limit" {
  description = "Burst request limit at stage level"
  type        = number
  default     = 50
}

variable "get_vehicle_invoke_arn" {
  description = "Lambda invoke ARN for GET /fleet/{truckId}"
  type        = string
}

variable "user_pool_arn" {
  description = "Cognito User Pool ARN for API Gateway authorizer"
  type        = string
}