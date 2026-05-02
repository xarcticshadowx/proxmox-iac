packer {
  required_plugins {
    proxmox = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "proxmox_url" { type = string }
variable "proxmox_node" { type = string }
variable "proxmox_username" { type = string }
variable "proxmox_token" {
  type      = string
  sensitive = true
  description = <<-EOT
    Full Proxmox API token string (user@realm!tokenid=secret).
    Prefers TF_VAR_proxmox_api_token (same as OpenTofu); if empty, uses PKR_VAR_proxmox_token.
    EOT
  default = env("TF_VAR_proxmox_api_token") != "" ? env("TF_VAR_proxmox_api_token") : env("PKR_VAR_proxmox_token")
}
variable "template_vm_id" { type = number }
variable "template_name" { type = string }
variable "iso_file" { type = string }
variable "virtio_iso_file" { type = string }
variable "vm_storage" { type = string }
variable "iso_storage" { type = string }
variable "bridge" { type = string }
variable "winrm_username" { type = string }
variable "winrm_password" {
  type        = string
  sensitive   = true
  description = "Defaults from WINRM_PASSWORD in the repo root .env."
  default     = env("WINRM_PASSWORD")
}

source "proxmox-iso" "win11" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  insecure_skip_tls_verify = true

  node          = var.proxmox_node
  vm_id         = var.template_vm_id
  vm_name       = var.template_name
  template_name = var.template_name

  iso_file    = var.iso_file
  unmount_iso = true

  qemu_agent = true
  os         = "win11"
  machine    = "q35"
  bios       = "ovmf"

  cores           = 4
  memory          = 8192
  scsi_controller = "virtio-scsi-single"

  disks {
    type         = "scsi"
    disk_size    = "80G"
    storage_pool = var.vm_storage
    format       = "raw"
    cache_mode   = "writeback"
  }

  network_adapters {
    model  = "virtio"
    bridge = var.bridge
  }

  additional_iso_files {
    iso_file = var.virtio_iso_file
    unmount  = true
  }

  additional_iso_files {
    iso_storage_pool = var.iso_storage
    cd_files = [
      "answer/Autounattend.xml",
      "scripts/bootstrap-winrm.ps1",
      "scripts/install-virtio.ps1",
      "scripts/install-qemu-agent.ps1",
      "scripts/baseline-windows.ps1",
      "scripts/sysprep.ps1"
    ]
    cd_label = "cidata"
    unmount  = true
  }

  communicator   = "winrm"
  winrm_username = var.winrm_username
  winrm_password = var.winrm_password
  winrm_timeout  = "6h"
}

build {
  sources = ["source.proxmox-iso.win11"]

  provisioner "powershell" {
    scripts = [
      "scripts/install-virtio.ps1",
      "scripts/install-qemu-agent.ps1",
      "scripts/baseline-windows.ps1"
    ]
  }

  provisioner "powershell" {
    script = "scripts/sysprep.ps1"
  }
}
