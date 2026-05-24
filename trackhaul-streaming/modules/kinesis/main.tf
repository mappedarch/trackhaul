resource "aws_kinesis_stream" "this" {
  name             = var.stream_name
  shard_count      = var.shard_count
  retention_period = var.retention_period_hours

  # KMS encryption — never use SSE_KINESIS managed key in regulated environments
  encryption_type = "KMS"
  kms_key_id      = var.kms_key_arn

  # Shard-level metrics — essential for detecting hot shards in production
  shard_level_metrics = [
    "IncomingBytes",
    "IncomingRecords",
    "OutgoingBytes",
    "OutgoingRecords",
    "WriteProvisionedThroughputExceeded",
    "ReadProvisionedThroughputExceeded",
    "IteratorAgeMilliseconds",
  ]

  tags = merge(var.tags, {
    Environment = var.environment
    Name        = var.stream_name
  })
}