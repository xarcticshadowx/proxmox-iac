# Run `packer/scripts/render-autounattend.ps1` (or .sh), or `scripts/packer-build-with-render.sh`,
# before `packer validate|build` so `answer/Autounattend.xml` is never the git placeholder (REPLACE_ME).
# iac-packer runs render on container start—recreate the container after changing WINRM_PASSWORD / PKR_VAR_*.
# Vars: PKR_VAR_win11_install_wim_index, PKR_VAR_win11_install_filename (default install.wim), WINRM_PASSWORD.
# Set PKR_VAR_win11_install_wim_index if index 6 is wrong (dism /Get-WimInfo).
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

  # Win11 boot ISO is the ONLY ide CD-ROM (ide0). virtio-win + cidata use SATA so OVMF's "DVD-ROM
  # QMxxxxx" list is not three IDE drives in plugin default order (QMxxxx numbers are QEMU-enumerated,
  # not ide slot numbers). First blue-menu entry was often not the full Windows media before this split.
  #
  # Shift+F10 troubleshooting: X: is WinPE (boot.wim RAMdisk); install.esd/install.wim live under
  # sources\ on the ide0 ISO volume (often D:–H:, not X:). Example: for %d in (D E F G H) do @dir %d:\sources\install.*
  boot_iso {
    iso_file = var.iso_file
    unmount  = true
    type     = "ide"
    index    = 0
  }

  boot = "order=ide0;sata0;sata1;scsi0;net0"

  # One Enter usually clears "Press any key to boot from CD/DVD…" on ide0 (Win11). Add extra "<enter>"
  # only if your firmware still stops at that prompt after the first key.
  boot_wait = "10s"
  boot_command = [
    "<wait20s>",
    "<enter>",
  ]

  qemu_agent = true
  os         = "win11"
  # Align with production qm VMs (e.g. pc-q35-10.1); plain "q35" uses a different QEMU profile.
  machine    = "pc-q35-10.1"
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
    type     = "sata"
    index    = 0
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
    type     = "sata"
    index    = 1
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
