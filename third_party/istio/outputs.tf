output "istio_ingress_port_http2" {
  value = [for k, v in data.kubernetes_service_v1.istio-ingress-svc.spec[0].port : v if v.name == "http2" || v.name == "https"]
}