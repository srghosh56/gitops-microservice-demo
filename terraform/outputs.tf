output "grafana" {
  description = "How to reach Grafana."
  value       = "kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80  ->  http://localhost:3000 (user: admin)"
}

output "prometheus" {
  description = "How to reach Prometheus."
  value       = "kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090  ->  http://localhost:9090"
}

output "argocd" {
  description = "How to reach the Argo CD UI."
  value       = "kubectl -n argocd port-forward svc/argocd-server 8080:80  ->  http://localhost:8080 (user: admin)"
}
