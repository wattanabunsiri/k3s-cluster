variable "kubeconfig_path" {
  type = string
}

variable "monitoring_namespace" {
  type    = string
  default = "monitoring"
}

variable "chart_version" {
  type    = string
  default = "65.5.1"
}

variable "grafana_admin_password" {
  type      = string
  sensitive = true
}

variable "retention_days" {
  type    = string
  default = "7d"
}

variable "discord_webhook_url" {
  type      = string
  sensitive = true
}