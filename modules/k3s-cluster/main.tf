terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.87"
    }
  }
  backend "local" {}
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true

  ssh {
    agent       = false
    username    = "root"
    private_key = file(pathexpand("~/.ssh/id_rsa"))

    node {
      name    = "pve"
      address = "10.10.10.205"
    }
  }
}

locals {
  k3s_install_cmd = { for name, s in var.servers : name =>
    s.role == "master" ? (
      "curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='server --token=${var.k3s_token} --tls-san=${var.master_ip}' sh -"
    ) : (
      "curl -sfL https://get.k3s.io | K3S_URL=https://${var.master_ip}:6443 K3S_TOKEN=${var.k3s_token} sh -"
    )
  }

  cloud_init_yaml = { for name, s in var.servers : name => <<-EOT
    #cloud-config
    hostname: ${name}
    package_update: true
    packages:
      - qemu-guest-agent
    runcmd:
      - systemctl enable --now qemu-guest-agent
      - ${local.k3s_install_cmd[name]}
    users:
      - name: debian
        groups: sudo
        shell: /bin/bash
        sudo: ALL=(ALL) NOPASSWD:ALL
        ssh_authorized_keys:
          - ${var.ssh_public_key}
  EOT
  }
}

module "vm" {
  for_each = var.servers
  source   = "./proxmox-vm"

  node_name = var.node_name
  vm_id     = each.value.vm_id
  name      = each.key
  tags      = ["k3s"]

  cloud_image_url    = var.cloud_image_url
  image_datastore    = var.image_datastore
  disk_datastore     = var.disk_datastore
  snippets_datastore = var.snippets_datastore
  disk_size          = each.value.disk_size

  cpu_cores = each.value.cores
  memory    = each.value.memory

  network_bridge = var.network_bridge
  ip_address     = each.value.ip
  gateway        = var.gateway

  user_data = local.cloud_init_yaml[each.key]
}

output "vm_ips" {
  value = { for k, m in module.vm : k => m.ip }
}