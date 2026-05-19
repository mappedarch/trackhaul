output "api_id" {
  description = "REST API ID"
  value       = aws_api_gateway_rest_api.this.id
}


output "api_endpoint" {
  description = "Invoke URL for the stage"
  value       = aws_api_gateway_stage.this.invoke_url
}

output "fleet_resource_id" {
  description = "Resource ID for /fleet — used by Lambda module Day 4"
  value       = aws_api_gateway_resource.fleet.id
}

output "fleet_truck_resource_id" {
  description = "Resource ID for /fleet/{truckId}"
  value       = aws_api_gateway_resource.fleet_truck.id
}

output "execution_arn" {
  description = "API Gateway execution ARN — passed to Lambda permission"
  value       = aws_api_gateway_rest_api.this.execution_arn
}