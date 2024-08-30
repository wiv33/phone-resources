locals {
  istio_repo_url = "https://istio-release.storage.googleapis.com/charts"
  version        = "1.23.0"
}

data "kubernetes_namespace" "istio-system" {
  metadata {
    name = "istio-system"
  }
}

resource "helm_release" "istio-base" {
  depends_on = [data.kubernetes_namespace.istio-system]
  repository   = local.istio_repo_url
  chart        = "base"
  name         = "istio-base"
  version      = local.version
  namespace    = data.kubernetes_namespace.istio-system.metadata.0.name

  set {
    name  = "defaultRevision"
    value = "default"
  }
}

resource "helm_release" "istiod" {
  depends_on = [helm_release.istio-base]
  repository = local.istio_repo_url
  chart      = "istiod"
  name       = "istiod"
  version    = local.version
  wait       = true
  namespace  = data.kubernetes_namespace.istio-system.metadata.0.name

  set {
    name  = "defaults.pilot.nodeSelector.kubernetes\\.io/hostname"
    value = "web-worker"
  }

  set {
    name  = "defaults.pilot.tolerations[0].key"
    value = "type"
  }
  set {
    name  = "defaults.pilot.tolerations[0].operator"
    value = "Equal"
  }
  set {
    name  = "defaults.pilot.tolerations[0].value"
    value = "web"
  }
  set {
    name  = "defaults.pilot.tolerations[0].effect"
    value = "NoSchedule"
  }
}


data "kubernetes_namespace" "istio-ingress" {
  metadata {
    name = "istio-ingress"
  }
}

# resource "kubernetes_namespace" "istio-ingress" {
#   metadata {
#     name = "istio-ingress"
#   }
# }

resource "helm_release" "istio-ingress" {
  depends_on = [helm_release.istio-base, helm_release.istiod]
  repository = local.istio_repo_url
  chart      = "gateway"
  name       = "istio-ingress"
  version    = local.version
  namespace  = data.kubernetes_namespace.istio-ingress.metadata.0.name
  wait       = true
  #   values = [file("../../istio/gateway/values.yaml")]

  set {
    name  = "defaults.tolerations[0].key"
    value = "type"
  }
  set {
    name  = "defaults.tolerations[0].operator"
    value = "Equal"
  }
  set {
    name  = "defaults.tolerations[0].value"
    value = "web"
  }
  set {
    name  = "defaults.tolerations[0].effect"
    value = "NoSchedule"
  }

  set {
    name  = "defaults.nodeSelector.kubernetes\\.io/hostname"
    value = "web-worker"
  }

}

resource "kubernetes_manifest" "gateway" {
  depends_on = [helm_release.istio-base, helm_release.istio-ingress]
  manifest = {
    apiVersion = "networking.istio.io/v1alpha3"
    kind       = "Gateway"

    metadata = {
      name      = "default-gateway"
      namespace = data.kubernetes_namespace.istio-ingress.metadata.0.name
    }

    spec = {
      selector = {
        istio = "ingress"
      }
      servers = [
        {
          port = {
            number   = 80
            name     = "http"
            protocol = "HTTP"
          }
          hosts = [
            var.domain,
            "*.${var.domain}"
          ]
        },
        {
          port = {
            number   = 443
            name     = "https"
            protocol = "HTTPS"
          }
          hosts = [
            var.domain,
            "*.${var.domain}"
          ]
          tls = {
            mode           = "SIMPLE"
            credentialName = var.tls_secret_name
          }
        },
        {
          port = {
            number   = 9092
            nodePort = 30092
            name     = "kafka-tcp"
            protocol = "TCP"
          }
          hosts = ["*"]
        },
        {
          port = {
            number   = 5432
            nodePort = 30543
            name     = "postgres-tcp"
            protocol = "TCP"
          }
          hosts = ["*"]
        }
      ]
    }
  }
}

data "kubernetes_service_v1" "istio-ingress-svc" {
  depends_on = [helm_release.istio-ingress]
  metadata {
    name      = "istio-ingress"
    namespace = data.kubernetes_namespace.istio-ingress.metadata.0.name
  }
}

locals {
  http2 = [
    for k, v in data.kubernetes_service_v1.istio-ingress-svc.spec[0].port :
    v if v.name == "http2"
  ][
  0
  ]
  https = [
    for k, v in data.kubernetes_service_v1.istio-ingress-svc.spec[0].port :
    v if v.name == "https"
  ][
  0
  ]
  istio_http_port     = local.http2.node_port
  istio_https_port    = local.https.node_port
  http_external_port  = local.http2.port
  https_external_port = local.https.port

  always_run = timestamp()
}

output "http_port_internal" {
  value = local.http_external_port
}

output "https_port_internal" {
  value = local.http_external_port
}

output "http_port_external" {
  value = local.istio_http_port
}

output "https_port_external" {
  value = local.istio_https_port
}

resource "null_resource" "delete_cookie" {
  provisioner "local-exec" {
    command = "rm -f res.txt"
  }
  triggers = {
    always_run = local.always_run
  }
}

resource "null_resource" "iptime_login" {
  depends_on = [helm_release.istio-ingress, data.kubernetes_service_v1.istio-ingress-svc, null_resource.delete_cookie]
  provisioner "local-exec" {
    command = "curl -XPOST --location ${var.iptime_host}/sess-bin/login_handler.cgi --header 'Referer: ${var.iptime_host}/sess-bin/login_handler.cgi' --form init_status='1' --form captcha_on=0 --form username=${var.iptime_username} --form passwd=${var.iptime_password} | awk -F\"'\" '/^setCookie\\(/ {print $2}' | tee res.txt"
  }
  triggers = {
    always_run = local.always_run
  }
}

data "local_file" "login_cookie" {
  depends_on = [null_resource.iptime_login]
  filename = "res.txt"
}

output "login" {
  value = base64decode(data.local_file.login_cookie.content_base64)
}


resource "null_resource" "iptime_assign_istio_http2_port_del" {
  depends_on = [data.local_file.login_cookie, null_resource.iptime_login]
  provisioner "local-exec" {
    command = "curl -XPOST --location '${var.iptime_host}/sess-bin/timepro.cgi' --header 'Cookie: efm_session_id=${base64decode(data.local_file.login_cookie.content_base64)}; Path=/ Expires=Thu, 01 Jan 1970 00:00:01 GMT; stay_login=1'  --header 'Content-Type: application/x-www-form-urlencoded' --header 'Referer: ${var.iptime_host}/sess-bin/timepro.cgi'  --data-urlencode 'tmenu=iframe'  --data-urlencode 'smenu=user_portforward'  --data-urlencode 'act=del'  --data-urlencode 'view_mode=user'  --data-urlencode 'mode=user'  --data-urlencode 'delcheck=${var.iptime_http_port_name}'"
  }
  triggers = {
    always_run = local.always_run
  }
}


resource "null_resource" "iptime_assign_istio_https_port_del" {
  depends_on = [null_resource.iptime_login, null_resource.iptime_assign_istio_http2_port_del]
  provisioner "local-exec" {
    command = "curl -XPOST --location '${var.iptime_host}/sess-bin/timepro.cgi' --header 'Cookie: efm_session_id=${base64decode(data.local_file.login_cookie.content_base64)}; Path=/ Expires=Thu, 01 Jan 1970 00:00:01 GMT; stay_login=1'  --header 'Content-Type: application/x-www-form-urlencoded' --header 'Referer: ${var.iptime_host}/sess-bin/timepro.cgi'  --data-urlencode 'tmenu=iframe'  --data-urlencode 'smenu=user_portforward'  --data-urlencode 'act=del'  --data-urlencode 'view_mode=user'  --data-urlencode 'mode=user'  --data-urlencode 'delcheck=${var.iptime_https_port_name}'"
  }
  triggers = {
    always_run = local.always_run
  }
}


resource "null_resource" "iptime_assign_istio_http2_port_add" {
  depends_on = [null_resource.iptime_login, null_resource.iptime_assign_istio_http2_port_del]
  provisioner "local-exec" {
    command = "sleep 1 && curl -XPOST --location '${var.iptime_host}/sess-bin/timepro.cgi' --header 'Cookie: efm_session_id=${base64decode(data.local_file.login_cookie.content_base64)}; Path=/ Expires=Thu, 01 Jan 1970 00:00:01 GMT; stay_login=1'  --header 'Content-Type: application/x-www-form-urlencoded' --header 'Referer: ${var.iptime_host}/sess-bin/timepro.cgi'  --data-urlencode 'tmenu=iframe'  --data-urlencode 'smenu=user_portforward'  --data-urlencode 'act=add'  --data-urlencode 'view_mode=user'  --data-urlencode 'mode=user'  --data-urlencode 'name=${var.iptime_http_port_name}'  --data-urlencode 'int_sport=${local.istio_http_port}'  --data-urlencode 'int_eport=${local.istio_http_port}'  --data-urlencode 'ext_sport=${local.http_external_port}'  --data-urlencode 'ext_eport=${local.http_external_port}'  --data-urlencode 'trigger_protocol='  --data-urlencode 'trigger_sport='  --data-urlencode 'trigger_eport='  --data-urlencode 'forward_ports='  --data-urlencode 'forward_protocol='  --data-urlencode 'internal_ip=${var.target_iptime_inner_server}'  --data-urlencode 'protocol=tcp'  --data-urlencode 'disabled=0'  --data-urlencode 'priority='  --data-urlencode 'old_priority='"
  }
  triggers = {
    always_run = tostring(local.always_run)
  }
}


resource "null_resource" "iptime_assign_istio_https_port_add" {
  depends_on = [
    null_resource.iptime_login, null_resource.iptime_assign_istio_https_port_del,
    null_resource.iptime_assign_istio_http2_port_add
  ]
  provisioner "local-exec" {
    command = "sleep 2 && curl -XPOST --location '${var.iptime_host}/sess-bin/timepro.cgi' --header 'Cookie: efm_session_id=${base64decode(data.local_file.login_cookie.content_base64)}; Path=/ Expires=Thu, 01 Jan 1970 00:00:01 GMT; stay_login=1'  --header 'Content-Type: application/x-www-form-urlencoded' --header 'Referer: ${var.iptime_host}/sess-bin/timepro.cgi'  --data-urlencode 'tmenu=iframe'  --data-urlencode 'smenu=user_portforward'  --data-urlencode 'act=add'  --data-urlencode 'view_mode=user'  --data-urlencode 'mode=user'  --data-urlencode 'name=${var.iptime_https_port_name}'  --data-urlencode 'int_sport=${local.istio_https_port}'  --data-urlencode 'int_eport=${local.istio_https_port}'  --data-urlencode 'ext_sport=${local.https_external_port}'  --data-urlencode 'ext_eport=${local.https_external_port}'  --data-urlencode 'trigger_protocol='  --data-urlencode 'trigger_sport='  --data-urlencode 'trigger_eport='  --data-urlencode 'forward_ports='  --data-urlencode 'forward_protocol='  --data-urlencode 'internal_ip=${var.target_iptime_inner_server}' --data-urlencode 'protocol=tcp'  --data-urlencode 'disabled=0'  --data-urlencode 'priority='  --data-urlencode 'old_priority='"
  }
  triggers = {
    always_run = tostring(local.always_run)
  }
}
