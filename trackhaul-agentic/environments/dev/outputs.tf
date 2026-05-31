output "queue_url" {
  description = "SQS queue URL — use this to send incident events"
  value       = module.agent_queue.queue_url
}

output "queue_arn" {
  description = "SQS queue ARN"
  value       = module.agent_queue.queue_arn
}

output "dlq_url" {
  description = "Dead letter queue URL — monitor this for failed incidents"
  value       = module.agent_queue.dlq_url
}

output "lambda_function_name" {
  description = "Agent handler Lambda function name"
  value       = module.agent_queue.lambda_function_name
}