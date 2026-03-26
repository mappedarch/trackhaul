# modules/config/outputs.tf

output "config_bucket_arn" {
  description = "ARN of the Config S3 bucket"
  value       = aws_s3_bucket.config.arn
}

output "config_recorder_id" {
  description = "ID of the Config recorder"
  value       = aws_config_configuration_recorder.this.id
}

output "config_aggregator_arn" {
  description = "ARN of the Config aggregator"
  value       = aws_config_configuration_aggregator.organization.arn
}