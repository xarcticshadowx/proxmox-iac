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
    Proxmox API token (same value as OpenTofu TF_VAR_proxmox_api_token / bpg provider).
    Reads env in order: TF_VAR_proxmox_api_token, PKR_VAR_proxmox_token, PROXMOX_TOKEN.
    EOT
  default = env("TF_VAR_proxmox_api_token") != "" ? env("TF_VAR_proxmox_api_token") : (
    env("PKR_VAR_proxmox_token") != "" ? env("PKR_VAR_proxmox_token") : env("PROXMOX_TOKEN")
  )
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

  boot_iso {
    iso_file = var.iso_file
    unmount  = true
  }

  # Disk before ISO: empty scsi0 is skipped on first boot → Win11 ISO (ide2). After setup writes
  # EFI to the disk, reboots boot Windows from scsi0 instead of re-entering setup from the ISO.
  # order=ide2;scsi0 first causes UEFI to prefer the ISO on every reboot → classic Windows setup loop.
  boot = "order=scsi0;ide2;net0"

  # If ide2 is already first in firmware, only "Press any key…" remains — one Enter.
  # If you still see the device picker with HARDDISK highlighted, add four "<down>" before "<enter>".
  boot_wait = "10s"
  boot_command = [
    "<wait18s>",
    "<enter>",
    "<wait8s>",
    "<enter>",
  ]

  qemu_agent = true
  os         = "win11"
  machine    = "q35"
  bios       = "ovmf"

  # Match production Win11 VMs (e.g. qm: cpu x86-64-v2-AES); avoids kvm64 default.
  cpu_type = "x86-64-v2-AES"

  # Required for OVMF: persistent EFI vars on cluster storage (avoids "no efidisk configured" / temporary efivars).
  efi_config {
    efi_storage_pool  = var.vm_storage
    efi_type          = "4m"
    pre_enrolled_keys = true
  }

  # Win11 setup expects TPM 2.0 (matches tofu tpm_state on clones); avoids PE/setup reboot loops.
  tpm_config {
    tpm_storage_pool = var.vm_storage
    tpm_version      = "v2.0"
  }

  cores           = 4
  memory          = 8192
  scsi_controller = "virtio-scsi-single"

  disks {
    type         = "scsi"
    disk_size    = "80G"
    storage_pool = var.vm_storage
    format       = "raw"
    cache_mode   = "writeback"
    io_thread    = true
    discard      = true
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

  # VirtIO + qemu-ga run from bootstrap-winrm.ps1 at first logon (required before WinRM connect).
  provisioner "powershell" {
    scripts = [
      "scripts/baseline-windows.ps1"
    ]
  }

  provisioner "powershell" {
    script = "scripts/sysprep.ps1"
  }
}
