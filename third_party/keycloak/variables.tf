variable "keycloak_admin_user" {
  description = "Keycloak admin user"
}
variable "keycloak_admin_password" {
  description = "Keycloak admin password"
}
variable "keycloak_host" {
  description = "Keycloak host"
}
variable "istio_gateway_name" {
  description = "Istio Gateway namespace and name"
  default     = "istio-ingress/default-gateway"
}

variable "keycloak_tls_secret" {
  description = "Keycloak TLS secret"
}

variable "kube_config_path" {
  description = "Path to the kubeconfig file"
}