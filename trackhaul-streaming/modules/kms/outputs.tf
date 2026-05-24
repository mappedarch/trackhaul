output "key_arn" {
  value = aws_kms_key.this.arn
}

output "key_id" {
  value = aws_kms_key.this.key_id
}

output "alias_name" {
  value = aws_kms_alias.this.name
}

output "ssm_parameter_name" {
  value = aws_ssm_parameter.key_arn.name
}