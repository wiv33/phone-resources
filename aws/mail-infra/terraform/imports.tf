# =============================================================================
# 기배포 리소스 흡수 (2026-07-20, bash 스크립트 01/02 로 최초 구축된 것들).
# 최초 1회 apply 에서 state 로 들어간다. 이후 이 파일은 삭제해도 무방하나
# 이력 문서로서 유지한다. plan 에서 이 리소스들에 변경이 나오면 코드-실물
# 불일치이므로 apply 전에 원인을 확인할 것.
# =============================================================================

import {
  to = aws_sesv2_email_identity.phoneshin
  id = "phoneshin.com"
}

import {
  to = aws_sesv2_email_identity_mail_from_attributes.phoneshin
  id = "phoneshin.com"
}

import {
  to = aws_ses_receipt_rule_set.inbound
  id = "phoneshin-inbound"
}

import {
  to = aws_ses_active_receipt_rule_set.active
  id = "phoneshin-inbound"
}

import {
  to = aws_ses_receipt_rule.bot_inbox_to_s3
  id = "phoneshin-inbound:bot-inbox-to-s3"
}

import {
  to = aws_s3_bucket.mail_inbox
  id = "phoneshin-mail-inbox-211125461385"
}

import {
  to = aws_s3_bucket_public_access_block.mail_inbox
  id = "phoneshin-mail-inbox-211125461385"
}

import {
  to = aws_s3_bucket_policy.mail_inbox
  id = "phoneshin-mail-inbox-211125461385"
}

import {
  to = aws_s3_bucket_lifecycle_configuration.mail_inbox
  id = "phoneshin-mail-inbox-211125461385"
}

import {
  to = aws_sns_topic.mail_received
  id = "arn:aws:sns:ap-northeast-2:211125461385:phoneshin-mail-received"
}

import {
  to = aws_sns_topic_policy.mail_received
  id = "arn:aws:sns:ap-northeast-2:211125461385:phoneshin-mail-received"
}

# Route53 (zone Z09303803VY8NM9IR48HD)
import {
  to = aws_route53_record.dkim["xy3cqsv4qzkznbfkx5pzygjdbhdjo4ls"]
  id = "Z09303803VY8NM9IR48HD_xy3cqsv4qzkznbfkx5pzygjdbhdjo4ls._domainkey.phoneshin.com_CNAME"
}

import {
  to = aws_route53_record.dkim["q46hgvczrkmzrpl74vbecpx5ns7iauf7"]
  id = "Z09303803VY8NM9IR48HD_q46hgvczrkmzrpl74vbecpx5ns7iauf7._domainkey.phoneshin.com_CNAME"
}

import {
  to = aws_route53_record.dkim["aqxptst3qo3iy7uqzzykygusnirtndqk"]
  id = "Z09303803VY8NM9IR48HD_aqxptst3qo3iy7uqzzykygusnirtndqk._domainkey.phoneshin.com_CNAME"
}

import {
  to = aws_route53_record.mailfrom_mx
  id = "Z09303803VY8NM9IR48HD_mail.phoneshin.com_MX"
}

import {
  to = aws_route53_record.mailfrom_spf
  id = "Z09303803VY8NM9IR48HD_mail.phoneshin.com_TXT"
}

import {
  to = aws_route53_record.dmarc
  id = "Z09303803VY8NM9IR48HD__dmarc.phoneshin.com_TXT"
}

import {
  to = aws_route53_record.recv_mx
  id = "Z09303803VY8NM9IR48HD_bot.phoneshin.com_MX"
}
