locals {
  function_name = "trackhaul-telemetry-consumer-${var.environment}"
}

# ─── IAM Role ────────────────────────────────────────────────────────────────

resource "aws_iam_role" "lambda_exec" {
  name = "${local.function_name}-role"

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

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.function_name}-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # CloudWatch Logs
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:log-group:/aws/lambda/${local.function_name}:*"
      },
      # Kinesis EFO — subscribe and read
      {
        Effect = "Allow"
        Action = [
          "kinesis:SubscribeToShard",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:DescribeStreamSummary",
          "kinesis:ListShards",
          "kinesis:RegisterStreamConsumer",
          "kinesis:DescribeStreamConsumer"
        ]
        Resource = [
          var.stream_arn,
          "${var.stream_arn}/*"
        ]
      },
      # EventBridge — put anomaly events
      {
        Effect   = "Allow"
        Action   = "events:PutEvents"
        Resource = "arn:aws:events:*:*:event-bus/${var.anomaly_event_bus_name}"
      },
      # KMS — decrypt environment variables
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = var.kms_key_arn
      },
      # SQS DLQ — send failed batch records
      {
        Effect = "Allow"
        Action = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.dlq.arn
      }
    ]
  })
}

# ─── EFO Consumer Registration ───────────────────────────────────────────────

resource "aws_kinesis_stream_consumer" "efo" {
  name       = "${local.function_name}-efo"
  stream_arn = var.stream_arn
}

# ─── Lambda Function ─────────────────────────────────────────────────────────

resource "aws_lambda_function" "consumer" {
  function_name = local.function_name
  role          = aws_iam_role.lambda_exec.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 60
  memory_size   = 256

  filename         = var.lambda_zip_path
  source_code_hash = filebase64sha256(var.lambda_zip_path)

  # Encrypt environment variables with CMK
  kms_key_arn = var.kms_key_arn

  environment {
    variables = {
      ANOMALY_EVENT_BUS_NAME = var.anomaly_event_bus_name
    }
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 30
  tags              = var.tags
}

# ─── EFO Event Source Mapping ────────────────────────────────────────────────

resource "aws_lambda_event_source_mapping" "kinesis_efo" {
  event_source_arn        = aws_kinesis_stream_consumer.efo.arn
  function_name           = aws_lambda_function.consumer.arn
  starting_position       = "LATEST"
  batch_size              = 100
  parallelization_factor  = 2   # 2 concurrent Lambda invocations per shard

  # Partial batch failure — only retry failed records, not the whole batch
  function_response_types = ["ReportBatchItemFailures"]

  bisect_batch_on_function_error = true  # halve the batch on error to isolate bad records

  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.dlq.arn
    }
  }

  depends_on = [aws_kinesis_stream_consumer.efo]
}

# ─── DLQ for failed batches ──────────────────────────────────────────────────

resource "aws_sqs_queue" "dlq" {
  name                      = "${local.function_name}-dlq"
  message_retention_seconds = 1209600  # 14 days
  kms_master_key_id         = var.kms_key_arn
  tags                      = var.tags
}
