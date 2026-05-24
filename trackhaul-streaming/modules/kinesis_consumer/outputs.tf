output "lambda_function_arn" {
  value = aws_lambda_function.consumer.arn
}

output "efo_consumer_arn" {
  value = aws_kinesis_stream_consumer.efo.arn
}

output "dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}