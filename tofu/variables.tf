variable "proxmox_endpoint" {
  type = string
}

variable "proxmox_api_token" {
  type      = string
  sensitive = true
}

variable "proxmox_ssh_user" {
  type    = string
  default = "root"
}

variable "proxmox_node" {
  type = string
}

variable "datastore" {
  type = string
}

variable "win11_template_id" {
  type = number
}

variable "vm_id" {
  type = number
}

variable "vm_name" {
  type = string
}

variable "bridge" {
  type    = string
  default = "vmbr0"
}
