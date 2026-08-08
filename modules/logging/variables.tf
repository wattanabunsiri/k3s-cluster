variable "kubeconfig_path" {
  type = string
}

variable "logging_namespace" {
  type    = string
  default = "logging"
}

variable "grafana_namespace" {
  type    = string
  default = "monitoring"
}

variable "chart_version" {
  type    = string
  default = "2.10.2"
}

variable "retention_days" {
  type    = number
  default = 7
}