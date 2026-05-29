# KMS key scoped exclusively to LLMOps SSM parameters
# Separate from other project KMS keys to enforce encryption boundary
resource "aws_kms_key" "llmops" {
  description             = "KMS key for TrackHaul LLMOps SSM prompt parameters"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Full access for root account — required, without this the key
        # becomes unmanageable if all other access is removed
        Sid    = "EnableRootAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::281136219737:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        # SSM service needs GenerateDataKey to encrypt parameters
        Sid    = "AllowSSMEncryption"
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "llmops" {
  name          = "alias/${local.prefix}"
  target_key_id = aws_kms_key.llmops.key_id
}