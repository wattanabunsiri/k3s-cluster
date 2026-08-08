variable "node_name" {
  type = string
}
variable "image_datastore" {
  type = string
}
variable "disk_datastore" {
  type = string
}
variable "snippets_datastore" {
  type = string
}
variable "cloud_image_url" {
  type = string
}
variable "gateway" {
  type = string
}
variable "network_bridge" {
  type    = string
  default = "vmbr0"
}
variable "ssh_public_key" {
  type = string
}
variable "k3s_token" {
  type      = string
  sensitive = true
}
variable "master_ip" {
  type = string
}
variable "servers" {
  type = map(object({
    vm_id     = number
    cores     = number
    memory    = number
    disk_size = number
    ip        = string
    role      = string
  }))
}
variable "proxmox_endpoint" {
  type = string
}
variable "proxmox_api_token" {
  type      = string
  sensitive = true
}