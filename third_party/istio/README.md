# Automate the binding of the istio-system and iptime port-forward

## Necessary
- `on-premise kubernetes`
- `terraform`
- `iptime`

## Required arguments
```
variable "kube_config_path" {
  description = "Path to the kubeconfig file"
}
variable "iptime_host" {
  description = "iptime host"
}

variable "iptime_username" {
  description = "iptime username"
}

variable "iptime_password" {
  description = "iptime password"
}

variable "iptime_http_port_name" {
  description = "iptime http port name"
}

variable "iptime_https_port_name" {
  description = "iptime https port name"
}

variable "target_iptime_inner_server" {
  description = "Target iptime inner server"
}

```
- kube_config_path
- iptime_host
- iptime_username
- iptime_password
- iptime_http_port_name
- iptime_https_port_name
- target_iptime_inner_server
