output "bucket_arn"  { value = aws_s3_bucket.kb_source.arn }
output "bucket_name" { value = aws_s3_bucket.kb_source.id }