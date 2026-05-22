output "bus_name" {
  description = "Name of the TrackHaul custom EventBridge bus"
  value       = aws_cloudwatch_event_bus.trackhaul.name
}

output "bus_arn" {
  description = "ARN of the TrackHaul custom EventBridge bus"
  value       = aws_cloudwatch_event_bus.trackhaul.arn
}

output "schema_registry_name" {
  description = "Name of the schema registry"
  value       = aws_schemas_registry.trackhaul.name
}