provider "kubernetes" {
  config_path = "~/.kube/shin_config"
}

resource "kubernetes_manifest" "postgresql-vs" {
  manifest = {
    apiVersion = "networking.istio.io/v1alpha3"
    kind       = "VirtualService"
    metadata = {
      name      = "postgresql"
      namespace = "database"
    }

    spec = {
      hosts = ["*"]
      gateways = ["istio-ingress/default-gateway"]
      tcp = [
        {
          match = [
            {
              port = 5432
            }
          ]
          route = [
            {
              destination = {
                host = "postgresql.database.svc.cluster.local"
                port = {
                  number = 5432
                }
              }
            }
          ]
        }
      ]
    }
  }
}