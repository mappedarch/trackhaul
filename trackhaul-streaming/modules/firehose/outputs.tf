output "delivery_stream_name" {
  value = aws_kinesis_firehose_delivery_stream.this.name
}

output "delivery_stream_arn" {
  value = aws_kinesis_firehose_delivery_stream.this.arn
}


output "firehose_role_arn" {
  description = "IAM role ARN assumed by Firehose — needed to grant KMS key policy access"
  value       = aws_iam_role.firehose.arn
}
