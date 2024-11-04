resource "kubernetes_secret_v1" "route53_credentials_secret" {
  metadata {
    name      = "route53-credentials-secret"
    namespace = "istio-ingress"
  }

  data = {
    access-key-id     = var.aws_access_key
    secret-access-key = var.aws_secret_key
  }

  type = "Opaque"
}

resource "kubernetes_manifest" "letsencrypt_dns01_route53_issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Issuer"

    metadata = {
      name      = "letsencrypt-dns01-route53-${var.domain_config_name}-issuer"
      namespace = "istio-ingress"
    }

    spec : {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = var.issuer_email

        privateKeySecretRef = {
          name = "letsencrypt-dns01-route53-${var.domain_config_name}-key-pair"
        }

        solvers = [
          {
            selector = {
              dnsZones = [
                var.domain
              ]
            }
            dns01 = {
              route53 = {
                region       = var.region
                hostedZoneID = var.zone_id

                accessKeyIDSecretRef = {
                  name = kubernetes_secret_v1.route53_credentials_secret.metadata[0].name
                  key  = "access-key-id"
                }
                secretAccessKeySecretRef = {
                  name = kubernetes_secret_v1.route53_credentials_secret.metadata[0].name
                  key  = "secret-access-key"
                }
              }
            }
          }
        ]
      }
    }
  }
}

resource "kubernetes_manifest" "certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"

    metadata = {
      name      = "${var.domain_config_name}-cert"
      namespace = "istio-ingress"
    }

    spec = {
      secretName = "${var.domain_config_name}-key-pair"
      commonName = var.domain

      dnsNames = [
        var.domain,
        "*.${var.domain}",
      ]

      duration = "2160h0m0s" # 90d
      renewBefore = "360h0m0s" # 15d

      privateKey = {
        algorithm = "RSA"
        encoding  = "PKCS1"
        size      = 4096
      }

      issuerRef = {
        kind  = "Issuer"
        group = "cert-manager.io"
        name  = kubernetes_manifest.letsencrypt_dns01_route53_issuer.manifest.metadata.name
      }
    }
  }
}
