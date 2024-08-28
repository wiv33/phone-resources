resource "kubernetes_manifest" "gateway-tcp" {
  manifest = {
    apiVersion = "networking.istio.io/v1alpha3"
    kind       = "Gateway"
    metadata = {
      name      = "tcp-gateway"
      namespace = "istio-ingress"
    }
    spec = {
      selector = {
        istio = "ingress"
      }
      servers = [
        {
          port = {
            number   = 9092
            name     = "kafka-tcp"
            protocol = "TCP"
          }
          hosts = ["*"]
        },
        {
          port = {
            number   = 5432
            name     = "postgres-tcp"
            protocol = "TCP"
          }
          hosts = ["*"]
        }
      ]
    }
  }
}