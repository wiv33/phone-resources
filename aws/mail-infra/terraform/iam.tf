# phone-api 전용 최소권한 사용자.
# access key 는 TF state 에 남기지 않기 위해 여기서 발급하지 않는다
# → ../10-issue-credentials.sh (발급 + k8s Secret 반영)

resource "aws_iam_user" "phone_api_mail" {
  name = "phone-api-mail-consumer"
  path = "/phoneshin/"
}

data "aws_iam_policy_document" "phone_api_mail" {
  statement {
    sid = "ConsumeMailQueue"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [aws_sqs_queue.mail_ingest.arn]
  }

  statement {
    sid       = "ReadMailObjects"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.mail_inbox.arn}/${local.key_prefix}*"]
  }
}

resource "aws_iam_user_policy" "phone_api_mail" {
  name   = "mail-ingest-consume"
  user   = aws_iam_user.phone_api_mail.name
  policy = data.aws_iam_policy_document.phone_api_mail.json
}
