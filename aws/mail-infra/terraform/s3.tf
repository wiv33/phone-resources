resource "aws_s3_bucket" "mail_inbox" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_public_access_block" "mail_inbox" {
  bucket                  = aws_s3_bucket.mail_inbox.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# SES 만 쓰기 가능 (해당 rule set 경유 + 이 계정 소유 검증)
resource "aws_s3_bucket_policy" "mail_inbox" {
  bucket = aws_s3_bucket.mail_inbox.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowSESPuts"
        Effect    = "Allow"
        Principal = { Service = "ses.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.mail_inbox.arn}/*"
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.account_id }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:ses:${var.region}:${local.account_id}:receipt-rule-set/${local.rule_set_name}:receipt-rule/*"
          }
        }
      }
    ]
  })
}

# 무한 축적 방지 (denial-of-wallet): 수신 원문은 기간 경과 후 자동 삭제
resource "aws_s3_bucket_lifecycle_configuration" "mail_inbox" {
  bucket = aws_s3_bucket.mail_inbox.id

  rule {
    id     = "expire-inbox"
    status = "Enabled"
    filter {
      prefix = local.key_prefix
    }
    expiration {
      days = var.mail_retention_days
    }
  }

  rule {
    id     = "abort-incomplete-mpu"
    status = "Enabled"
    filter {
      prefix = ""
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
