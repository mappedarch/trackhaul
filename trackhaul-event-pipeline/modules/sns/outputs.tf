output "critical_alerts_arn" {
  description = "ARN of the critical alerts SNS topic"
  value       = aws_sns_topic.critical_alerts.arn
}

output "maintenance_alerts_arn" {
  description = "ARN of the maintenance alerts SNS topic"
  value       = aws_sns_topic.maintenance_alerts.arn
}