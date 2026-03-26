# modules/cloudtrail/outputs.tf

output "cloudtrail_bucket_arn" {
  description = "ARN of the CloudTrail S3 bucket"
  value       = aws_s3_bucket.cloudtrail.arn
}

output "cloudtrail_bucket_id" {
  description = "Name of the CloudTrail S3 bucket"
  value       = aws_s3_bucket.cloudtrail.id
}

output "cloudtrail_arn" {
  description = "ARN of the Organization CloudTrail"
  value       = aws_cloudtrail.organization.arn
}