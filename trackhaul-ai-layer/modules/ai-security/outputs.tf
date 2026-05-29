output "s3_kb_kms_key_arn" {
  value = aws_kms_key.s3_kb.arn
}

output "dynamodb_kms_key_arn" {
  value = aws_kms_key.dynamodb.arn
}

output "cloudwatch_kms_key_arn" {
  value = aws_kms_key.cloudwatch.arn
}

output "fleet_intelligence_lambda_role_arn" {
  value = aws_iam_role.fleet_intelligence_lambda.arn
}

output "token_tracker_lambda_role_arn" {
  value = aws_iam_role.token_tracker_lambda.arn
}