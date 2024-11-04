data "kubernetes_namespace" "argo-ns" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  chart      = "argo-cd"
  repository = "https://argoproj.github.io/argo-helm"
  name       = "argocd"
  namespace  = data.kubernetes_namespace.argo-ns.metadata.0.name
  version    = "6.9.3"
#   values = [
#     file("${path.module}/values.yaml")
#   ]
  set {
    name  = "global.domain"
    value = "argo.phoneshin.com"
  }

  /*
  global.nodeSelector:
    kubernetes.io/hostname: "devops-worker"
   */
  set {
    name  = "global.nodeSelector\\.kubernetes\\.io/hostname"
    value = "devops-worker"
  }

  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }

/*
  배포 후 웹 콘솔 접근해서 변경 필요
  여기서는 반영이 안 됨.
  set {
    name  = "configs.secret.argocdServerAdminPassword"
    value = "Asdfqwer1!"
  }
*/
}

data "kubernetes_secret_v1" "argocd_server_admin_password" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = data.kubernetes_namespace.argo-ns.metadata.0.name
  }
}

resource "kubernetes_manifest" "argocd-virtual-service" {
  depends_on = [helm_release.argocd]
  manifest = {
    apiVersion = "networking.istio.io/v1alpha3"
    kind       = "VirtualService"
    metadata = {
      name      = "argocd-vs"
      namespace = "argocd"
    }
    spec = {
      hosts = ["argo.phoneshin.com"]
      gateways = ["istio-ingress/default-gateway"]
      http = [
        {
          match = [
            {
              uri = {
                prefix = "/"
              }
            }
          ]
          route = [
            {
              destination = {
                host = "argocd-server"
                port = {
                  number = 443
                }
              }
            }
          ]
        }
      ]
    }
  }
}