# Platform layer for the demo: monitoring (Prometheus, Grafana, kube-state-metrics)
# and Argo CD. The application itself is NOT managed here; Argo CD deploys it from Git.

resource "helm_release" "monitoring" {
  name             = "monitoring"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.kube_prometheus_stack_version
  namespace        = "monitoring"
  create_namespace = true
  timeout          = 900

  values = [file("${path.module}/values/kube-prometheus-stack.yaml")]

  set_sensitive {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argo_cd_version
  namespace        = "argocd"
  create_namespace = true
  timeout          = 900

  values = [file("${path.module}/values/argo-cd.yaml")]
}
