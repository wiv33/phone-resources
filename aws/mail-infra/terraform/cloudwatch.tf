# DLQ 적체 알람 (선택): var.alarm_email 설정 시에만 생성.
# 이메일 구독은 수신자가 확인 메일의 링크를 눌러야 활성화된다.

resource "aws_sns_topic" "mail_ops_alarm" {
  count = var.alarm_email == "" ? 0 : 1
  name  = "phoneshin-mail-ops-alarm"
}

resource "aws_sns_topic_subscription" "mail_ops_email" {
  count     = var.alarm_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.mail_ops_alarm[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  count               = var.alarm_email == "" ? 0 : 1
  alarm_name          = "phoneshin-mail-ingest-dlq-not-empty"
  alarm_description   = "메일 인제스트 DLQ 에 메시지 적체 - 컨슈머 장애 또는 poison message"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.mail_ingest_dlq.name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.mail_ops_alarm[0].arn]
}
