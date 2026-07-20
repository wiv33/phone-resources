locals {
  ttl = 600
}

resource "aws_route53_record" "dkim" {
  for_each = toset(local.dkim_tokens)

  zone_id = data.aws_route53_zone.phoneshin.zone_id
  name    = "${each.value}._domainkey.${var.domain}"
  type    = "CNAME"
  ttl     = local.ttl
  records = ["${each.value}.dkim.amazonses.com"]
}

resource "aws_route53_record" "mailfrom_mx" {
  zone_id = data.aws_route53_zone.phoneshin.zone_id
  name    = var.mailfrom_domain
  type    = "MX"
  ttl     = local.ttl
  records = ["10 feedback-smtp.${var.region}.amazonses.com"]
}

resource "aws_route53_record" "mailfrom_spf" {
  zone_id = data.aws_route53_zone.phoneshin.zone_id
  name    = var.mailfrom_domain
  type    = "TXT"
  ttl     = local.ttl
  records = ["v=spf1 include:amazonses.com ~all"]
}

resource "aws_route53_record" "dmarc" {
  zone_id = data.aws_route53_zone.phoneshin.zone_id
  name    = "_dmarc.${var.domain}"
  type    = "TXT"
  ttl     = local.ttl
  records = ["v=DMARC1; p=none; rua=mailto:${local.dmarc_rua}"]
}

resource "aws_route53_record" "recv_mx" {
  zone_id = data.aws_route53_zone.phoneshin.zone_id
  name    = var.recv_domain
  type    = "MX"
  ttl     = local.ttl
  records = ["10 inbound-smtp.${var.region}.amazonaws.com"]
}
