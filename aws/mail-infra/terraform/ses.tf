# ---------- 발신 identity (Easy DKIM) ----------
resource "aws_sesv2_email_identity" "phoneshin" {
  email_identity = var.domain

  dkim_signing_attributes {
    next_signing_key_length = "RSA_2048_BIT"
  }
}

resource "aws_sesv2_email_identity_mail_from_attributes" "phoneshin" {
  email_identity         = aws_sesv2_email_identity.phoneshin.email_identity
  mail_from_domain       = var.mailfrom_domain
  behavior_on_mx_failure = "USE_DEFAULT_VALUE"
}

# ---------- 수신 rule ----------
resource "aws_ses_receipt_rule_set" "inbound" {
  rule_set_name = local.rule_set_name
}

resource "aws_ses_active_receipt_rule_set" "active" {
  rule_set_name = aws_ses_receipt_rule_set.inbound.rule_set_name
}

# TLS Require: STARTTLS 없는 평문 SMTP 반송 (현실적 발신자는 전부 지원)
resource "aws_ses_receipt_rule" "bot_inbox_to_s3" {
  name          = local.rule_name
  rule_set_name = aws_ses_receipt_rule_set.inbound.rule_set_name
  recipients    = [var.recv_domain]
  enabled       = true
  scan_enabled  = true
  tls_policy    = "Require"

  s3_action {
    position          = 1
    bucket_name       = aws_s3_bucket.mail_inbox.bucket
    object_key_prefix = local.key_prefix
    topic_arn         = aws_sns_topic.mail_received.arn
  }

  depends_on = [aws_s3_bucket_policy.mail_inbox, aws_sns_topic_policy.mail_received]
}
