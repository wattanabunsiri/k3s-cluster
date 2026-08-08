variable "node_name" {
  type = string
}

variable "vm_id" {
  type = number
}

variable "name" {
  type = string
}

variable "description" {
  type    = string
  default = "Managed by Terraform"
}

variable "tags" {
  type    = list(string)
  default = []
}

variable "started" {
  type    = bool
  default = true
}

variable "cloud_image_url" {
  type    = string
  default = ""
}

variable "cloud_image_file_id" {
  type    = string
  default = ""
}

variable "cloud_image_filename" {
  type    = string
  default = ""
}

variable "image_datastore" {
  type = string
}

variable "snippets_datastore" {
  type    = string
  default = "local"
}

variable "disk_datastore" {
  type = string
}

variable "disk_size" {
  type    = number
  default = 20
}

variable "clone_template" {
  type    = string
  default = ""
}

variable "cpu_cores" {
  type    = number
  default = 2
}

variable "cpu_type" {
  type    = string
  default = "x86-64-v2-AES"
}

variable "memory" {
  type    = number
  default = 2048
}

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "ip_address" {
  type = string
}

variable "gateway" {
  type    = string
  default = ""
}

variable "enable_qemu_agent" {
  type    = bool
  default = true
}

variable "user_data" {
  type    = string
  default = ""
}

variable "data_disks" {
  type = list(object({
    datastore_id = string
    size_gb      = number
  }))
  default = []
}