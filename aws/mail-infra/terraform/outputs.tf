output "sqs_queue_url" {
  description = "phone-api SqsBridge 가 폴링할 큐 URL"
  value       = aws_sqs_queue.mail_ingest.url
}

output "sqs_dlq_url" {
  value = aws_sqs_queue.mail_ingest_dlq.url
}

output "mail_bucket" {
  description = "수신 원문(MIME) 버킷"
  value       = aws_s3_bucket.mail_inbox.bucket
}

output "sns_topic_arn" {
  value = aws_sns_topic.mail_received.arn
}

output "iam_user" {
  description = "phone-api 소비자 IAM 사용자 (키 발급은 10-issue-credentials.sh)"
  value       = aws_iam_user.phone_api_mail.name
}

output "region" {
  value = var.region
}
