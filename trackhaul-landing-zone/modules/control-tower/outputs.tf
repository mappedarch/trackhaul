output "landing_zone_arn" {
  description = "ARN of the CT landing zone"
  value       = aws_controltower_landing_zone.this.arn
}

output "landing_zone_version" {
  description = "Deployed CT landing zone version"
  value       = aws_controltower_landing_zone.this.version
}

output "drift_status" {
  description = "CT landing zone drift status"
  value       = aws_controltower_landing_zone.this.drift_status
}
