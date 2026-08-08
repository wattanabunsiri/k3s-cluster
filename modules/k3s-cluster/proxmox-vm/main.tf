terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.87"
    }
  }
}

resource "proxmox_download_file" "cloud_image" {
  count        = var.cloud_image_url != "" && var.cloud_image_file_id == "" ? 1 : 0
  content_type = "import"
  datastore_id = var.image_datastore
  node_name    = var.node_name
  url          = var.cloud_image_url
  file_name    = var.cloud_image_filename != "" ? var.cloud_image_filename : null
  overwrite    = false
}

resource "proxmox_virtual_environment_file" "user_data" {
  count        = var.user_data != "" ? 1 : 0
  content_type = "snippets"
  datastore_id = var.snippets_datastore
  node_name    = var.node_name
  source_raw {
    data      = var.user_data
    file_name = "${var.name}-user-data.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  node_name   = var.node_name
  vm_id       = var.vm_id
  name        = var.name
  description = var.description
  tags        = var.tags
  started     = var.started

  serial_device {}

  dynamic "agent" {
    for_each = var.enable_qemu_agent ? [1] : []
    content {
      enabled = true
    }
  }

  cpu {
    cores = var.cpu_cores
    type  = var.cpu_type
  }

  memory {
    dedicated = var.memory
  }

  disk {
    datastore_id = var.disk_datastore
    file_id = (
      var.cloud_image_file_id != "" ? var.cloud_image_file_id :
      var.cloud_image_url != "" ? proxmox_download_file.cloud_image[0].id :
      null
    )
    size        = var.disk_size
    interface   = "scsi0"
    file_format = "raw"
  }

  dynamic "disk" {
    for_each = var.data_disks
    content {
      datastore_id = disk.value.datastore_id
      size         = disk.value.size_gb
      interface    = "scsi${disk.key + 1}"
      file_format  = "raw"
    }
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  dynamic "clone" {
    for_each = var.clone_template != "" ? [1] : []
    content {
      vm_id = var.clone_template
    }
  }

  initialization {
    datastore_id = var.disk_datastore
    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway != "" ? var.gateway : null
      }
    }
    user_data_file_id = var.user_data != "" ? proxmox_virtual_environment_file.user_data[0].id : null
  }

  lifecycle {
    ignore_changes = [
      initialization,
    ]
  }
}