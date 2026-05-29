# -------------------------------------------------------
# Feedback Capture Lambda Role
# Writes dispatcher feedback into DynamoDB
# -------------------------------------------------------
resource "aws_iam_role" "feedback_capture" {
  name = "trackhaul-feedback-capture-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "feedback_capture" {
  name = "feedback-capture-policy"
  role = aws_iam_role.feedback_capture.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Write feedback records to DynamoDB only
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.feedback.arn
      },
      {
        # Encrypt/decrypt DynamoDB data
        Effect = "Allow"
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ]
        Resource = var.kms_key_arn
      },
      {
        # CloudWatch logs
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# -------------------------------------------------------
# Feedback Reingestion Lambda Role
# Reads approved corrections and writes to golden dataset S3
# -------------------------------------------------------
resource "aws_iam_role" "feedback_reingest" {
  name = "trackhaul-feedback-reingest-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "feedback_reingest" {
  name = "feedback-reingest-policy"
  role = aws_iam_role.feedback_reingest.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Read approved corrections from DynamoDB
        Effect = "Allow"
        Action = [
          "dynamodb:Query",
          "dynamodb:UpdateItem"
        ]
        Resource = [
          aws_dynamodb_table.feedback.arn,
          "${aws_dynamodb_table.feedback.arn}/index/eval-candidate-index"
        ]
      },
      {
        # Write new golden dataset version to S3
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.golden_dataset_bucket}",
          "arn:aws:s3:::${var.golden_dataset_bucket}/${var.golden_dataset_prefix}/*"
        ]
      },
      {
        # Encrypt/decrypt DynamoDB and S3 data
        Effect = "Allow"
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ]
        Resource = var.kms_key_arn
      },
      {
        # CloudWatch logs
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}
