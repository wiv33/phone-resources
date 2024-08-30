variable "kube_config_path" {
  description = "Path to the kubeconfig file"
}
variable "iptime_host" {
  description = "Iptime host"
}

variable "iptime_username" {
  description = "Iptime username"
}

variable "iptime_password" {
  description = "Iptime password"
}

variable "iptime_http_port_name" {
  description = "Iptime http port name"
}

variable "iptime_https_port_name" {
  description = "Iptime https port name"
}

variable "target_iptime_inner_server" {
  description = "Target iptime inner server"
}

variable "domain" {
  description = "Domain for the application"
}

variable "records_cname" {
  description = "IP address for the records"
}

variable "records_ip" {
  description = "IP address for the records"
}

variable "tls_secret_name" {
  description = "Name of the tls secret"
}

variable "aws_secret_key" {
  description = "AWS secret key"
}
variable "aws_access_key" {
  description = "AWS access key"
}
variable "zone_id" {
  description = "Zone id of route53"
}