
resource "aws_route53_record" "main_domain" {
  name    = var.domain
  type    = "A"
  ttl     = 300
  zone_id = var.zone_id
  records = var.records_ip
}

resource "aws_route53_record" "asterisk_main_domain" {
  depends_on = [aws_route53_record.main_domain]
  name    = "*.${var.domain}"
  type    = "CNAME"
  ttl     = 300
  zone_id = var.zone_id
  records = var.records_cname
}

resource "aws_route53_record" "double_asterisk_main_domain" {
  depends_on = [aws_route53_record.asterisk_main_domain]
  name    = "*.*.${var.domain}"
  type    = "CNAME"
  ttl     = 300
  zone_id = var.zone_id
  records = var.records_cname
}

