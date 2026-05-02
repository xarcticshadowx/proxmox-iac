resource "proxmox_virtual_environment_vm" "win11_dev" {
  name        = var.vm_name
  description = "Windows 11 dev workstation managed by OpenTofu"
  tags        = ["windows", "dev", "rdp", "opentofu", "portainer"]

  node_name = var.proxmox_node
  vm_id     = var.vm_id

  clone {
    vm_id = var.win11_template_id
    full  = true
  }

  agent {
    enabled = true
  }

  operating_system {
    type = "win11"
  }

  machine = "q35"
  bios    = "ovmf"

  cpu {
    type  = "host"
    cores = 6
  }

  memory {
    dedicated = 32768
  }

  efi_disk {
    datastore_id = var.datastore
    file_format  = "raw"
  }

  tpm_state {
    datastore_id = var.datastore
    version      = "v2.0"
  }

  disk {
    datastore_id = var.datastore
    interface    = "scsi0"
    size         = 256
    file_format  = "raw"
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  started = true
}
