include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../modules/argocd"
}

inputs = {
  kubeconfig_path = "/Users/terz/.kube/k3s-config"
}