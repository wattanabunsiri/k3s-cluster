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

resource "kubernetes_namespace" "logging" {
  metadata {
    name = var.logging_namespace
  }
}

# ── Loki (chart ใหม่ ไม่ใช่ loki-stack ที่ deprecated) ──
resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "6.18.0"
  namespace  = kubernetes_namespace.logging.metadata[0].name

  values = [
    <<-EOT
    deploymentMode: SingleBinary
    loki:
      commonConfig:
        replication_factor: 1
      storage:
        type: filesystem
      auth_enabled: false
      schemaConfig:
        configs:
          - from: "2024-01-01"
            store: tsdb
            object_store: filesystem
            schema: v13
            index:
              prefix: loki_index_
              period: 24h
    singleBinary:
      replicas: 1
      resources:
        requests:
          memory: 256Mi
          cpu: 50m
        limits:
          memory: 512Mi
    chunksCache:
      enabled: false
    resultsCache:
      enabled: false
    read:
      replicas: 0
    write:
      replicas: 0
    backend:
      replicas: 0
    monitoring:
      selfMonitoring:
        enabled: false
      lokiCanary:
        enabled: false
    test:
      enabled: false
    gateway:
      enabled: false
    EOT
  ]
}

# ── Promtail (chart แยกต่างหาก) ──
resource "helm_release" "promtail" {
  name       = "promtail"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  version    = "6.16.6"
  namespace  = kubernetes_namespace.logging.metadata[0].name

  values = [
    <<-EOT
    config:
      clients:
        - url: http://loki.${kubernetes_namespace.logging.metadata[0].name}.svc.cluster.local:3100/loki/api/v1/push
    resources:
      requests:
        memory: 32Mi
        cpu: 25m
      limits:
        memory: 64Mi
    EOT
  ]

  depends_on = [helm_release.loki]
}

resource "kubernetes_config_map" "loki_datasource" {
  metadata {
    name      = "loki-datasource"
    namespace = var.grafana_namespace
    labels = {
      grafana_datasource = "1"
    }
  }

  data = {
    "loki-datasource.yaml" = <<-EOT
      apiVersion: 1
      datasources:
        - name: Loki
          type: loki
          access: proxy
          url: http://loki.${kubernetes_namespace.logging.metadata[0].name}.svc.cluster.local:3100
          isDefault: false
          editable: true
    EOT
  }
}

output "namespace" {
  value = kubernetes_namespace.logging.metadata[0].name
}