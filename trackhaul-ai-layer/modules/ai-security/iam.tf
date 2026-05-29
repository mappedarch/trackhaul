# -------------------------------------------------------
# Lambda execution role — Fleet Intelligence Handler
# Invokes Bedrock, queries KB, reads/writes DynamoDB cache
# -------------------------------------------------------
resource "aws_iam_role" "fleet_intelligence_lambda" {
  name = "${var.project}-fleet-intelligence-lambda-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "fleet_intelligence_bedrock" {
  name = "bedrock-invoke-retrieve"
  role = aws_iam_role.fleet_intelligence_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
            "bedrock:InvokeModel",
            "bedrock:ApplyGuardrail"
            ]
        Resource = [
          "arn:aws:bedrock:eu-central-1:${var.account_id}:inference-profile/eu.anthropic.claude-sonnet-4-5-20250929-v1:0",
          "arn:aws:bedrock:eu-west-1:${var.account_id}:inference-profile/eu.anthropic.claude-sonnet-4-5-20250929-v1:0",
          "arn:aws:bedrock:eu-west-1:${var.account_id}:inference-profile/eu.anthropic.claude-haiku-4-5-20251001-v1:0",
          "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-haiku-20240307-v1:0",
          "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0",
          "arn:aws:bedrock:*::foundation-model/anthropic.claude-haiku-4-5-20251001-v1:0",
          "arn:aws:bedrock:eu-central-1:${var.account_id}:guardrail/*",
          "arn:aws:bedrock:eu-west-1:${var.account_id}:guardrail/*"
        ]
      },
      {
        Effect = "Allow"
        Action = ["bedrock:Retrieve", "bedrock:RetrieveAndGenerate"]
        Resource = "arn:aws:bedrock:eu-central-1:${var.account_id}:knowledge-base/*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "fleet_intelligence_dynamodb" {
  name = "dynamodb-cache-readwrite"
  role = aws_iam_role.fleet_intelligence_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query"
        ]
        Resource = [
          "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/trackhaul-vehicles-dev",
          "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/trackhaul-vehicles-dev/index/*",
          "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/trackhaul-dev-rag-cache",
          "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/trackhaul-dev-circuit-breaker",
          "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/trackhaul-token-tracker-dev"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "fleet_intelligence_kms" {
  name = "kms-decrypt-dynamodb"
  role = aws_iam_role.fleet_intelligence_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
      Resource = compact([
        aws_kms_key.dynamodb.arn,
        var.vehicles_table_kms_key_arn
      ])
    }]
  })
}

resource "aws_iam_role_policy_attachment" "fleet_intelligence_basic" {
  role       = aws_iam_role.fleet_intelligence_lambda.name
  # Basic execution = CloudWatch Logs write only. Nothing else.
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# -------------------------------------------------------
# Lambda execution role — Token Tracker
# Writes token metrics to DynamoDB only
# -------------------------------------------------------
resource "aws_iam_role" "token_tracker_lambda" {
  name = "${var.project}-token-tracker-lambda-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "token_tracker_dynamodb" {
  name = "dynamodb-token-write"
  role = aws_iam_role.token_tracker_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:PutItem", "dynamodb:UpdateItem"]
      Resource = "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/trackhaul-*"
    }]
  })
}

resource "aws_iam_role_policy" "token_tracker_kms" {
  name = "kms-decrypt-dynamodb"
  role = aws_iam_role.token_tracker_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
      Resource = aws_kms_key.dynamodb.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "token_tracker_basic" {
  role       = aws_iam_role.token_tracker_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# -------------------------------------------------------
# Patch: add KMS Decrypt to existing bedrock-kb role
# The KB role was created in modules/bedrock-kb/iam.tf
# It needs kms:Decrypt to read CMK-encrypted S3 objects
# -------------------------------------------------------
resource "aws_iam_role_policy" "bedrock_kb_kms" {
  name = "kms-decrypt-s3-kb"
  # This name must match the role name in modules/bedrock-kb/iam.tf
  role = "trackhaul-bedrock-kb-role-${var.environment}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
      Resource = aws_kms_key.s3_kb.arn
    }]
  })
}