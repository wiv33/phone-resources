provider "aws" {
  profile = var.aws_profile
  region  = var.region
}

data "aws_caller_identity" "current" {}

data "aws_route53_zone" "phoneshin" {
  name         = "${var.domain}."
  private_zone = false
}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  bucket_name = "phoneshin-mail-inbox-${local.account_id}"
  dmarc_rua   = "dmarc@${var.recv_domain}" # DMARC 리포트도 같은 수신 파이프라인으로

  # Easy DKIM 토큰: identity 에 고정 발급된 값 (aws sesv2 get-email-identity 로 확인 가능).
  # identity 를 재생성하지 않는 한 바뀌지 않는다. 재생성 시 여기와 imports.tf 갱신.
  dkim_tokens = [
    "xy3cqsv4qzkznbfkx5pzygjdbhdjo4ls",
    "q46hgvczrkmzrpl74vbecpx5ns7iauf7",
    "aqxptst3qo3iy7uqzzykygusnirtndqk",
  ]

  rule_set_name = "phoneshin-inbound"
  rule_name     = "bot-inbox-to-s3"
  key_prefix    = "inbox/"
}
