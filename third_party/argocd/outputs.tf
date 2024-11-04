output "argo_cd_url" {
  value = helm_release.argocd.metadata.0
}

output "argocd_server_admin_password" {
  value = nonsensitive(data.kubernetes_secret_v1.argocd_server_admin_password.data["password"])
}