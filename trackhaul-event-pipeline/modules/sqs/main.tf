# ---------------------------------------------------------------
# DLQ — created first, referenced by the main queue redrive policy
# ---------------------------------------------------------------
resource "aws_sqs_queue" "dlq" {
  name = "${var.project}-${var.consumer_name}-dlq-${var.environment}"

  message_retention_seconds = 1209600

  kms_master_key_id = var.kms_key_arn

  tags = merge(var.tags, {
    Name     = "${var.project}-${var.consumer_name}-dlq-${var.environment}"
    Consumer = var.consumer_name
    Type     = "dlq"
  })
}

# ---------------------------------------------------------------
# Main queue with redrive policy pointing to DLQ
# ---------------------------------------------------------------
resource "aws_sqs_queue" "main" {
  name = "${var.project}-${var.consumer_name}-${var.environment}"

  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  kms_master_key_id = var.kms_key_arn

  tags = merge(var.tags, {
    Name     = "${var.project}-${var.consumer_name}-${var.environment}"
    Consumer = var.consumer_name
    Type     = "main"
  })
}

# ---------------------------------------------------------------
# Queue policy — allows EventBridge to send messages
# ---------------------------------------------------------------
data "aws_iam_policy_document" "sqs_eventbridge_policy" {
  statement {
    sid    = "AllowEventBridgeSend"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.main.arn]
  }
}

resource "aws_sqs_queue_policy" "main" {
  queue_url = aws_sqs_queue.main.id
  policy    = data.aws_iam_policy_document.sqs_eventbridge_policy.json
}

# ---------------------------------------------------------------
# CloudWatch alarm — fires if any message lands in the DLQ
# ---------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name          = "${var.project}-${var.consumer_name}-dlq-not-empty-${var.environment}"
  alarm_description   = "Messages detected in DLQ for ${var.consumer_name}. Investigate immediately."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = var.tags
}
