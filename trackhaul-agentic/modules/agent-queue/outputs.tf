output "queue_url" {
  description = "SQS queue URL for sending incident events"
  value       = aws_sqs_queue.incident_agent.url
}

output "queue_arn" {
  description = "SQS queue ARN"
  value       = aws_sqs_queue.incident_agent.arn
}

output "dlq_url" {
  description = "Dead letter queue URL for failed incidents"
  value       = aws_sqs_queue.incident_agent_dlq.url
}

output "dlq_arn" {
  description = "Dead letter queue ARN"
  value       = aws_sqs_queue.incident_agent_dlq.arn
}

output "lambda_function_name" {
  description = "Agent handler Lambda function name"
  value       = aws_lambda_function.agent_handler.function_name
}

output "lambda_function_arn" {
  description = "Agent handler Lambda function ARN"
  value       = aws_lambda_function.agent_handler.arn
}

output "escalation_queue_url" {
  description = "Escalation queue URL — for incidents requiring human review"
  value       = aws_sqs_queue.incident_escalation.url
}

output "escalation_queue_arn" {
  description = "Escalation queue ARN"
  value       = aws_sqs_queue.incident_escalation.arn
}