output "api_endpoint" {
  description = "Fleet API invoke URL"
  value       = module.api_gateway.api_endpoint
}

output "user_pool_id" {
  value = module.cognito.user_pool_id
}

output "client_id" {
  value = module.cognito.client_id
}