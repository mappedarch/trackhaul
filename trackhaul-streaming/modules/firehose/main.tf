# IAM role that Firehose assumes
resource "aws_iam_role" "firehose" {
  name = "trackhaul-firehose-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "firehose" {
  name = "trackhaul-firehose-policy-${var.environment}"
  role = aws_iam_role.firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Read from Kinesis source stream
        Effect = "Allow"
        Action = [
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:DescribeStream",
          "kinesis:ListShards"
        ]
        Resource = var.kinesis_stream_arn
      },
      {
        # Write to S3
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ]
        Resource = [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
            "kms:GenerateDataKey",
            "kms:Decrypt"
        ]
        Resource = [
            var.kms_key_arn,           # S3 encryption key
            var.kinesis_kms_key_arn    # Kinesis stream decryption key
        ]
        },
      {
        # Glue schema access for Parquet conversion
        Effect = "Allow"
        Action = [
          "glue:GetTable",
          "glue:GetTableVersion",
          "glue:GetTableVersions"
        ]
        Resource = "*"
      },
      {
        # CloudWatch logs for delivery errors
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/firehose/trackhaul-telemetry-${var.environment}"
  retention_in_days = 30
  tags              = var.tags
}

resource "aws_cloudwatch_log_stream" "firehose" {
  name           = "delivery"
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

resource "aws_kinesis_firehose_delivery_stream" "this" {
  name        = "trackhaul-telemetry-${var.environment}"
  destination = "extended_s3"

  # Source: read from Kinesis Data Stream
  kinesis_source_configuration {
    kinesis_stream_arn = var.kinesis_stream_arn
    role_arn           = aws_iam_role.firehose.arn
  }

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = var.s3_bucket_arn

    # Buffer: flush at 128MB or 5 minutes — balance between cost and freshness
    buffering_size     = 128
    buffering_interval = 300

    # Parquet conversion via Glue schema
    data_format_conversion_configuration {
      enabled = true

      input_format_configuration {
        deserializer {
          open_x_json_ser_de {}
        }
      }

      output_format_configuration {
        serializer {
          parquet_ser_de {
            compression = "SNAPPY"
          }
        }
      }

      schema_configuration {
        role_arn      = aws_iam_role.firehose.arn
        database_name = var.glue_database_name
        table_name    = var.glue_table_name
        region        = var.aws_region
      }
    }

    # Partition by date — keeps Athena scan costs low
    prefix              = "telemetry/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "errors/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = aws_cloudwatch_log_stream.firehose.name
    }
  }

  tags = var.tags
}