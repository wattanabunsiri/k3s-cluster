variable "kubeconfig_path" {
  type = string
}

variable "argocd_namespace" {
  type    = string
  default = "argocd"
}

variable "argocd_chart_version" {
  type    = string
  # Staged upgrade off 7.7.11 (ArgoCD v2.13.2), which was too old for k8s v1.36:
  # its structured-merge-diff didn't know .status.terminatingReplicas, so
  # ServerSideApply wedged the monitoring app at sync status Unknown.
  # Step 1 of 2 (done): 7.9.1 is the last 2.x chart (v2.14.11). Upgrading to it
  # first meant the 2.x -> 3.0 jump started from the version ArgoCD's own
  # "2.14 to 3.0" upgrade guide assumes.
  # Step 2 of 2: 10.3.0 -> ArgoCD v3.5.0. Its k8s client libraries know
  # .status.terminatingReplicas, which is what unblocks ServerSideApply and
  # lets argocd-apps/stack/monitoring.yaml drop skipCrds.
  default = "10.3.0"
}