# phone-api(온프레미스)가 long-polling 으로 소비하는 내구 버퍼.
# 홈 회선/클러스터 장애 시에도 메일 이벤트가 최대 14일 보존된다.

resource "aws_sqs_queue" "mail_ingest_dlq" {
  name                      = "phoneshin-mail-ingest-dlq"
  message_retention_seconds = 1209600 # 14d
}

resource "aws_sqs_queue" "mail_ingest" {
  name                      = "phoneshin-mail-ingest"
  message_retention_seconds = 1209600 # 14d
  # Kafka 프로듀서 delivery.timeout.ms(기본 120s) 를 넉넉히 초과해야
  # in-flight send 도중 메시지가 가시화되어 중복 발행/조기 DLQ 되지 않는다.
  visibility_timeout_seconds = 300
  receive_wait_time_seconds  = 20 # long polling

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.mail_ingest_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue_policy" "mail_ingest" {
  queue_url = aws_sqs_queue.mail_ingest.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowSNSDelivery"
        Effect    = "Allow"
        Principal = { Service = "sns.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.mail_ingest.arn
        Condition = { ArnEquals = { "aws:SourceArn" = aws_sns_topic.mail_received.arn } }
      }
    ]
  })
}

# raw delivery: SQS body = SES 수신 알림 JSON 그대로 (SNS 봉투 없음).
# 컨슈머는 receipt.spamVerdict/virusVerdict/spfVerdict/dkimVerdict 를 신뢰 소스로 사용할 것.
resource "aws_sns_topic_subscription" "mail_to_sqs" {
  topic_arn            = aws_sns_topic.mail_received.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.mail_ingest.arn
  raw_message_delivery = true

  depends_on = [aws_sqs_queue_policy.mail_ingest]
}
