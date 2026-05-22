# Custom EventBridge bus for all TrackHaul application events
resource "aws_cloudwatch_event_bus" "trackhaul" {
  name = "${var.project}-${var.environment}-fleet-events"

  tags = var.tags
}

# Archive — enables event replay for debugging and reprocessing
# Retention set to 90 days for GDPR-aware audit window
resource "aws_cloudwatch_event_archive" "trackhaul" {
  count = var.enable_archive ? 1 : 0

  name             = "${var.project}-${var.environment}-archive"
  event_source_arn = aws_cloudwatch_event_bus.trackhaul.arn

  # Archive all events — refine with event_pattern if cost becomes a concern
  retention_days = var.archive_retention_days
}

# Schema registry — auto-discover event schemas as they flow through the bus
resource "aws_schemas_registry" "trackhaul" {
  name        = "${var.project}-${var.environment}-registry"
  description = "Schema registry for TrackHaul fleet events"

  tags = var.tags
}

# Schema discoverer — automatically infers schemas from events on the bus
resource "aws_schemas_discoverer" "trackhaul" {
  source_arn  = aws_cloudwatch_event_bus.trackhaul.arn
  description = "Auto-discover schemas from TrackHaul fleet events"

  tags = var.tags
}

# ---------------------------------------------------------------
# IAM role — allows EventBridge to send messages to SQS queues
# Scoped to this account only
# ---------------------------------------------------------------
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_role" "eventbridge_sqs" {
  name = "${var.project}-${var.environment}-eventbridge-sqs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "eventbridge_sqs" {
  name = "send-to-consumer-queues"
  role = aws_iam_role.eventbridge_sqs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["sqs:SendMessage"]
      # Scoped to the four consumer queues only
      Resource = [
        var.geofence_queue_arn,
        var.fuel_anomaly_queue_arn,
        var.driver_scoring_queue_arn,
        var.maintenance_queue_arn
      ]
    }]
  })
}

# ---------------------------------------------------------------
# EventBridge rules — one per consumer
# Each rule matches on detail-type and routes to its SQS queue
# Source locked to trackhaul.fleet to prevent accidental matches
# ---------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "geofence" {
  name           = "${var.project}-${var.environment}-geofence-rule"
  description    = "Routes geofence breach events to the geofence SQS queue"
  event_bus_name = aws_cloudwatch_event_bus.trackhaul.name

  event_pattern = jsonencode({
    source      = ["trackhaul.fleet"]
    detail-type = ["GEOFENCE_BREACH"]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "geofence" {
  rule           = aws_cloudwatch_event_rule.geofence.name
  event_bus_name = aws_cloudwatch_event_bus.trackhaul.name
  target_id      = "geofence-sqs"
  arn            = var.geofence_queue_arn
  role_arn       = aws_iam_role.eventbridge_sqs.arn
}

resource "aws_cloudwatch_event_rule" "fuel_anomaly" {
  name           = "${var.project}-${var.environment}-fuel-anomaly-rule"
  description    = "Routes fuel anomaly events to the fuel anomaly SQS queue"
  event_bus_name = aws_cloudwatch_event_bus.trackhaul.name

  event_pattern = jsonencode({
    source      = ["trackhaul.fleet"]
    detail-type = ["FUEL_ANOMALY"]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "fuel_anomaly" {
  rule           = aws_cloudwatch_event_rule.fuel_anomaly.name
  event_bus_name = aws_cloudwatch_event_bus.trackhaul.name
  target_id      = "fuel-anomaly-sqs"
  arn            = var.fuel_anomaly_queue_arn
  role_arn       = aws_iam_role.eventbridge_sqs.arn
}

resource "aws_cloudwatch_event_rule" "driver_scoring" {
  name           = "${var.project}-${var.environment}-driver-scoring-rule"
  description    = "Routes driver score update events to the driver scoring SQS queue"
  event_bus_name = aws_cloudwatch_event_bus.trackhaul.name

  event_pattern = jsonencode({
    source      = ["trackhaul.fleet"]
    detail-type = ["DRIVER_SCORE_UPDATE"]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "driver_scoring" {
  rule           = aws_cloudwatch_event_rule.driver_scoring.name
  event_bus_name = aws_cloudwatch_event_bus.trackhaul.name
  target_id      = "driver-scoring-sqs"
  arn            = var.driver_scoring_queue_arn
  role_arn       = aws_iam_role.eventbridge_sqs.arn
}

resource "aws_cloudwatch_event_rule" "maintenance" {
  name           = "${var.project}-${var.environment}-maintenance-rule"
  description    = "Routes maintenance required events to the maintenance SQS queue"
  event_bus_name = aws_cloudwatch_event_bus.trackhaul.name

  event_pattern = jsonencode({
    source      = ["trackhaul.fleet"]
    detail-type = ["MAINTENANCE_REQUIRED"]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "maintenance" {
  rule           = aws_cloudwatch_event_rule.maintenance.name
  event_bus_name = aws_cloudwatch_event_bus.trackhaul.name
  target_id      = "maintenance-sqs"
  arn            = var.maintenance_queue_arn
  role_arn       = aws_iam_role.eventbridge_sqs.arn
}