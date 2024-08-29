terraform {
  required_providers {
    helm = {
      source = "hashicorp/helm"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

provider "helm" {
  kubernetes {
    config_path = var.kube_config_path
  }
}

provider "kubernetes" {
  config_path = var.kube_config_path
}


resource "kubernetes_namespace" "harbor" {
  metadata {
    name = "harbor"
  }
}

// helm install my-release oci://registry-1.docker.io/bitnamicharts/harbor
// repository = "https://helm.goharbor.io"
resource "helm_release" "harbor" {
  repository = "oci://registry-1.docker.io/bitnamicharts"
  chart      = "harbor"
  name       = "harbor"
  namespace  = kubernetes_namespace.harbor.metadata[0].name
  version    = "23.0.1"
  replace    = true

  set {
    name  = "expose.type"
    value = "ClusterIP"
  }

  set {
    name  = "expose.tls.auto.commonName"
    value = "harbor"
  }

  set {
    name  = "externalURL"
    value = "https://${var.harbor_host}"
  }
  #   harborAdminPassword: "Harbor12345"
  #   adminPassword: "${var.harbor_admin_password}"
  set {
    name  = "harborAdminPassword"
    value = var.harbor_admin_password
  }

  set {
    name  = "adminPassword"
    value = var.harbor_admin_password
  }

  set {
    name  = "service.type"
    value = "ClusterIP"
  }

  set {
    name  = "portal.nodeSelector.kubernetes\\.io/hostname"
    value = "devops-worker"
  }

  set {
    name  = "core.nodeSelector.kubernetes\\.io/hostname"
    value = "devops-worker"
  }
  set {
    name  = "registry.nodeSelector.kubernetes\\.io/hostname"
    value = "devops-worker"
  }
  set {
    name  = "jobservice.nodeSelector.kubernetes\\.io/hostname"
    value = "devops-worker"
  }

}

resource "kubernetes_manifest" "harbor_vs" {
  manifest = {
    apiVersion = "networking.istio.io/v1alpha3"
    kind       = "VirtualService"
    metadata = {
      name      = "harbor-vs"
      namespace = kubernetes_namespace.harbor.metadata[0].name
    }
    spec = {
      hosts = [var.harbor_host]
      gateways = [var.istio_gateway_name]
      http = [
        {
          match = [
            {
              uri = {
                prefix = "/c/"
              }
            },
            {
              uri = {
                prefix = "/api"
              },
            },
            {
              uri = {
                prefix = "/service"
              }
            },
            {
              uri = {
                prefix = "/chartrepo"
              }
            }
          ]
          route = [
            {
              destination = {
                host = "harbor-core.harbor.svc.cluster.local"
                port = {
                  number = 80
                }
              }
            }
          ]
        },
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
                host = "harbor-portal.harbor.svc.cluster.local"
                port = {
                  number = 80
                }
              }
            }
          ]
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "harbor_registry_vs" {
  manifest = {
    apiVersion = "networking.istio.io/v1alpha3"
    kind       = "VirtualService"
    metadata = {
      name      = "harbor-registry-vs"
      namespace = kubernetes_namespace.harbor.metadata[0].name
    }
    spec = {
      hosts = ["registry-${var.harbor_host}"]
      gateways = [var.istio_gateway_name]
      http = [
        {
          match = [
            {
              uri = {
                prefix = "/v2"
              }
            }
          ]
          route = [
            {
              destination = {
                host = "harbor-core.harbor.svc.cluster.local"
                port = {
                  number = 80
                }
              }
            }
          ]
        },
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
                host = "harbor-registry.harbor.svc.cluster.local"
                port = {
                  number = 5000
                }
              }
            }
          ]
        }
      ]
    }
  }
}