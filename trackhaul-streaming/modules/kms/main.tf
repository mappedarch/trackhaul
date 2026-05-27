data "aws_iam_policy_document" "key_policy" {
  # Root account admin access — required, otherwise you can lock yourself out permanently
  statement {
    sid    = "EnableRootAdminAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Service principal — e.g. Kinesis encrypting/decrypting records
  statement {
    sid    = "AllowServicePrincipal"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = [var.allowed_service_principal]
    }
    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt",
    ]
    resources = ["*"]
  }

  # Specific IAM roles — Lambda, Firehose etc added here explicitly
  dynamic "statement" {
    for_each = length(var.allowed_iam_arns) > 0 ? [1] : []
    content {
      sid    = "AllowIAMRoles"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = var.allowed_iam_arns
      }
      actions = [
        "kms:GenerateDataKey",
        "kms:Decrypt",
        "kms:DescribeKey",
      ]
      resources = ["*"]
    }
  }
}

resource "aws_kms_key" "this" {
  description             = var.description
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.key_policy.json

  # Prevents accidental destroy — critical for encryption keys in production
  # lifecycle {
  #   prevent_destroy = true
  # }

  tags = merge(var.tags, {
    Environment = var.environment
  })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.alias_name}"
  target_key_id = aws_kms_key.this.key_id
}

# Publish ARN to SSM so other modules can reference it without hardcoding
resource "aws_ssm_parameter" "key_arn" {
  name  = "/trackhaul/${var.environment}/kms/${var.alias_name}/arn"
  type  = "String"
  value = aws_kms_key.this.arn

  tags = merge(var.tags, {
    Environment = var.environment
  })
}