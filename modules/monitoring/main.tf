terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15"
    }
  }
  backend "local" {}
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.monitoring_namespace
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "monitoring"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.chart_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  # ── Prometheus ──────────────────────────────
  set {
    name  = "grafana.podDnsConfig.options[0].name"
    value = "ndots"
  }
  set {
    name  = "grafana.podDnsConfig.options[0].value"
    value = "2"
  }
  set {
    name  = "grafana.podDnsPolicy"
    value = "ClusterFirst"
  }
  set {
    name  = "prometheus.prometheusSpec.retention"
    value = var.retention_days
  }
  set {
    name  = "prometheus.prometheusSpec.resources.requests.memory"
    value = "300Mi"
  }
  set {
    name  = "prometheus.prometheusSpec.resources.requests.cpu"
    value = "100m"
  }
  set {
    name  = "prometheus.prometheusSpec.resources.limits.memory"
    value = "700Mi"
  }

  # ── Grafana ──────────────────────────────────
  set {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }
  set {
    name  = "grafana.service.type"
    value = "ClusterIP"
  }
  set {
    name  = "grafana.resources.requests.memory"
    value = "128Mi"
  }
  set {
    name  = "grafana.resources.requests.cpu"
    value = "50m"
  }
  set {
    name  = "grafana.resources.limits.memory"
    value = "256Mi"
  }

  # ── kube-state-metrics ──────────────────────
  set {
    name  = "kube-state-metrics.resources.requests.memory"
    value = "64Mi"
  }
  set {
    name  = "kube-state-metrics.resources.limits.memory"
    value = "128Mi"
  }

  # ── node-exporter (รันบนทุก node) ────────────
  set {
    name  = "prometheus-node-exporter.resources.requests.memory"
    value = "32Mi"
  }
  set {
    name  = "prometheus-node-exporter.resources.limits.memory"
    value = "64Mi"
  }

  # ── prometheus-operator ─────────────────────
  set {
    name  = "prometheusOperator.resources.requests.memory"
    value = "128Mi"
  }
  set {
    name  = "prometheusOperator.resources.limits.memory"
    value = "256Mi"
  }

  # ── Alertmanager ─────────────────────────────
  set {
    name  = "alertmanager.enabled"
    value = "true"
  }
  set {
    name  = "alertmanager.alertmanagerSpec.resources.requests.memory"
    value = "64Mi"
  }
  set {
    name  = "alertmanager.alertmanagerSpec.resources.limits.memory"
    value = "128Mi"
  }
  values = [
    <<-EOT
    grafana:
      dnsPolicy: ClusterFirst
      dnsConfig:
        options:
          - name: ndots
            value: "2"
    alertmanager:
      config:
        global:
          resolve_timeout: 5m
        route:
          receiver: 'discord'
          group_by: ['alertname', 'namespace']
          group_wait: 30s
          group_interval: 5m
          repeat_interval: 4h
          routes:
            - receiver: 'null'
              matchers:
                - alertname = "Watchdog"
        receivers:
          - name: 'null'
          - name: 'discord'
            discord_configs:
              - webhook_url: '${var.discord_webhook_url}'
                send_resolved: true
    EOT
  ]
}

output "namespace" {
  value = kubernetes_namespace.monitoring.metadata[0].name
}