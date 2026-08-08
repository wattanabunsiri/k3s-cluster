include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../modules/k3s-cluster"
}

inputs = {
  proxmox_endpoint  = get_env("PROXMOX_VE_ENDPOINT")
  proxmox_api_token = get_env("PROXMOX_VE_API_TOKEN")

  node_name          = "pve"
  image_datastore    = "local"
  disk_datastore     = "local-lvm"
  snippets_datastore = "local"
  network_bridge     = "vmbr0"

  cloud_image_url = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"

  gateway        = "192.168.1.1"
  ssh_public_key = get_env("K3S_SSH_PUBLIC_KEY")

  k3s_token = get_env("K3S_CLUSTER_TOKEN")
  master_ip = "192.168.1.211"

  servers = {
    "k3s-master" = {
      vm_id     = 101
      cores     = 2
      memory    = 4096
      disk_size = 40
      ip        = "192.168.1.211/24"
      role      = "master"
    }
    "k3s-worker-1" = {
      vm_id     = 102
      cores     = 4
      memory    = 4096
      disk_size = 30
      ip        = "192.168.1.212/24"
      role      = "worker"
    }
    "k3s-worker-2" = {
      vm_id     = 103
      cores     = 4
      memory    = 4096
      disk_size = 30
      ip        = "192.168.1.213/24"
      role      = "worker"
    }
  }
}