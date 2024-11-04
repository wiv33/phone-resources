variable "kube_config_path" {
  description = "Path to the kube config file"
}

variable "aws_access_key" {
  description = "AWS access key"
}

variable "aws_secret_key" {
  description = "AWS secret key"
}

variable "zone_id" {
  description = "Zone id of route53"
}

variable "region" {
  description = "AWS region"
}

variable "aws_account" {}

variable "domain" {
  description = "Domain name"
}

variable "domain_config_name" {
  description = "Domain config name"
}

variable "issuer_email" {
  description = "Email address for letsencrypt"
}