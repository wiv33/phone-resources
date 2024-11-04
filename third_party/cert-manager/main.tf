resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"
  }
}

resource "helm_release" "cert_manager" {
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  name       = "cert-manager"
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name
  version    = "v1.15.3"

  /*
  podDnsPolicy: "ClusterFirst"
   */
  set {
    name  = "podDnsPolicy"
    value = "None"
  }
  /*
  extraArgs:
   - "--dns01-recursive-nameservers-only=true"
   - "--dns01-recursive-nameservers=1.1.1.1:53,8.8.8.8:53"
   */
  set {
    name  = "extraArgs[0]"
    value = "--dns01-recursive-nameservers-only=true"
  }

  set {
    name  = "extraArgs[1]"
    value = "--dns01-recursive-nameservers=8.8.8.8:53"
  }

  /*
  podDnsConfig:
 nameservers:
   - "1.1.1.1"
   - "8.8.8.8"
   */
  set {
    name  = "podDnsConfig.nameservers[0]"
    value = "1.1.1.1"
  }

  set {
    name  = "podDnsConfig.nameservers[1]"
    value = "8.8.8.8"
  }

  set {
    name  = "dns01RecursiveNameservers"
    value = "8.8.8.8:53"
  }

  set {
    name  = "dns01RecursiveNameserversOnly"
    value = "true"
  }

  set {
    name  = "installCRDs"
    value = "true"
  }

  // cert-manager
  set {
    name  = "tolerations[0].key"
    value = "type"
  }
  set {
    name  = "tolerations[0].operator"
    value = "Equal"
  }
  set {
    name  = "tolerations[0].value"
    value = "web"
  }
  set {
    name  = "tolerations[0].effect"
    value = "NoSchedule"
  }

  // webhook
  set {
    name  = "webhook.tolerations[0].key"
    value = "type"
  }

  set {
    name  = "webhook.tolerations[0].operator"
    value = "Equal"
  }

  set {
    name  = "webhook.tolerations[0].value"
    value = "web"
  }

  set {
    name  = "webhook.tolerations[0].effect"
    value = "NoSchedule"
  }

  // carinjector
  set {
    name  = "cainjector.tolerations[0].key"
    value = "type"
  }

  set {
    name  = "cainjector.tolerations[0].operator"
    value = "Equal"
  }

  set {
    name  = "cainjector.tolerations[0].value"
    value = "web"
  }

  set {
    name  = "cainjector.tolerations[0].effect"
    value = "NoSchedule"
  }

  //startupapicheck

  set {
    name  = "startupapicheck.tolerations[0].key"
    value = "type"
  }
  set {
    name  = "startupapicheck.tolerations[0].operator"
    value = "Equal"
  }
  set {
    name  = "startupapicheck.tolerations[0].value"
    value = "web"
  }
  set {
    name  = "startupapicheck.tolerations[0].effect"
    value = "NoSchedule"
  }
}
