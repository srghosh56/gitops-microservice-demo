variable "kubeconfig_path" {
  description = "Path to the kubeconfig file."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "kubeconfig context of the kind cluster created by `make cluster`."
  type        = string
  default     = "kind-skao-demo"
}

variable "grafana_admin_password" {
  description = "Grafana admin password. Pass it as TF_VAR_grafana_admin_password; never commit it."
  type        = string
  sensitive   = true
}

variable "kube_prometheus_stack_version" {
  description = "Chart version to pin. null installs the latest; pin a version for reproducible installs."
  type        = string
  default     = null
}

variable "argo_cd_version" {
  description = "Chart version to pin. null installs the latest; pin a version for reproducible installs."
  type        = string
  default     = null
}
