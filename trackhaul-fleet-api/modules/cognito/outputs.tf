output "user_pool_id" {
  description = "Cognito User Pool ID — used by API Gateway authorizer"
  value       = aws_cognito_user_pool.fleet.id
}

output "user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = aws_cognito_user_pool.fleet.arn
}

output "client_id" {
  description = "App client ID — used in Postman auth configuration"
  value       = aws_cognito_user_pool_client.fleet_api.id
}

output "user_pool_endpoint" {
  description = "Cognito endpoint for token validation"
  value       = aws_cognito_user_pool.fleet.endpoint
}