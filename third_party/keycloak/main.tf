# install keycloak
resource "helm_release" "bitnami_keycloak" {
  chart      = "keycloak"
  repository = "https://charts.bitnami.com/bitnami"
  name       = "keycloak"
  namespace  = "keycloak"
  version    = "22.2.2"
  replace    = true
  timeout    = 120

  set {
    name  = "nodeSelector.kubernetes\\.io/hostname"
    value = "stateful-worker"
  }

  set {
    name  = "auth.adminUser"
    value = var.keycloak_admin_user
  }

  set {
    name  = "auth.adminPassword"
    value = var.keycloak_admin_password
  }

  set {
    name  = "tls.exsistingSecret"
    value = var.keycloak_tls_secret
  }

  set {
    name  = "production"
    value = "true"
  }

  set {
    name  = "proxy"
    value = "none"
  }

  set {
    name  = "tls.enabled"
    value = "true"
  }

  set {
    name  = "tls.autoGenerated"
    value = "true"
  }

  set {
    name  = "usePem"
    value = "true"
  }

  set {
    name  = "resources.requests.cpu"
    value = "500m"
  }

  set {
    name  = "resources.requests.memory"
    value = "1024Mi"
  }

  set {
    name  = "resources.limits.cpu"
    value = "1000m"
  }

  set {
    name  = "resources.limits.memory"
    value = "2048Mi"
  }

}


resource "kubernetes_manifest" "keycloak_vs" {
  manifest = {
    apiVersion = "networking.istio.io/v1alpha3"
    kind       = "VirtualService"
    metadata = {
      name      = "keycloak-vs"
      namespace = "keycloak"
    }
    spec = {
      hosts = [var.keycloak_host]
      gateways = [var.istio_gateway_name]
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
                host = "keycloak-headless.keycloak.svc.cluster.local"
                port = {
                  number = 8080
                }
              }
            }
          ]
        }
      ]
    }
  }
}