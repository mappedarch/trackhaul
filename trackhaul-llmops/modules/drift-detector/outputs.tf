output "drift_detector_function_name" {
  description = "Drift detector Lambda function name"
  value       = aws_lambda_function.drift_detector.function_name
}

output "drift_alerts_topic_arn" {
  description = "SNS topic ARN for drift alerts"
  value       = aws_sns_topic.drift_alerts.arn
}

output "drift_detector_log_group" {
  description = "CloudWatch log group for drift detector"
  value       = aws_cloudwatch_log_group.drift_detector.name
}
