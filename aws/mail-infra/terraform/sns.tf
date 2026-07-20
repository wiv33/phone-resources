resource "aws_sns_topic" "mail_received" {
  name = "phoneshin-mail-received"
}

resource "aws_sns_topic_policy" "mail_received" {
  arn = aws_sns_topic.mail_received.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "OwnerFullAccess"
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action = [
          "SNS:Subscribe", "SNS:Receive", "SNS:Publish",
          "SNS:GetTopicAttributes", "SNS:SetTopicAttributes",
          "SNS:ListSubscriptionsByTopic", "SNS:DeleteTopic",
          "SNS:AddPermission", "SNS:RemovePermission",
        ]
        Resource  = aws_sns_topic.mail_received.arn
        Condition = { StringEquals = { "AWS:SourceOwner" = local.account_id } }
      },
      {
        Sid       = "AllowSESPublish"
        Effect    = "Allow"
        Principal = { Service = "ses.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.mail_received.arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.account_id }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:ses:${var.region}:${local.account_id}:receipt-rule-set/${local.rule_set_name}:receipt-rule/*"
          }
        }
      },
    ]
  })
}
