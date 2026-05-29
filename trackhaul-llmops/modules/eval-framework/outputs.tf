output "eval_bucket_name" {
  description = "S3 bucket name for golden dataset and eval results"
  value       = aws_s3_bucket.eval.id
}

output "eval_bucket_arn" {
  description = "ARN — used when scoping Lambda execution role policy in a future day"
  value       = aws_s3_bucket.eval.arn
}
