variable "aws_profile" {
  description = "phoneshin.com 존을 보유한 AWS 계정 프로파일"
  type        = string
  default     = "auto"
}

variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "domain" {
  description = "발신 identity 도메인 (Easy DKIM)"
  type        = string
  default     = "phoneshin.com"
}

variable "recv_domain" {
  description = "자동화 수신 전용 서브도메인 (apex MX 는 비워둠 - 추후 직원용 메일과 충돌 방지)"
  type        = string
  default     = "bot.phoneshin.com"
}

variable "mailfrom_domain" {
  description = "SES custom MAIL FROM (발신 봉투 도메인)"
  type        = string
  default     = "mail.phoneshin.com"
}

variable "mail_retention_days" {
  description = "수신 원문(inbox/) S3 보관 일수"
  type        = number
  default     = 180
}

variable "alarm_email" {
  description = "DLQ 적체 알람 수신 이메일 (빈 값이면 알람 미생성)"
  type        = string
  default     = ""
}
