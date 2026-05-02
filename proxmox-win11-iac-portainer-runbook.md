# Windows 11 Dev VM on Proxmox with Portainer, Packer, OpenTofu, and Ansible

This runbook assumes you already have a Docker host managed by Portainer and you prefer to create/manage the automation tooling as Portainer stacks. The workflow still uses Packer for the Windows template, OpenTofu for Proxmox VM deployment, and Ansible for guest configuration, but the tools run as containers instead of being installed directly on a new automation VM.

## Target architecture

```text
Existing Docker host
  └── Portainer
      └── Stack: proxmox-win11-iac
          ├── packer one-shot container
          ├── tofu one-shot container
          └── ansible one-shot container

Proxmox
  ├── ISO storage
  │   ├── Windows 11 ISO
  │   └── virtio-win ISO
  ├── Windows 11 template built by Packer
  └── Windows 11 dev VM clone deployed by OpenTofu
```

Packer remains the image-builder layer because the official Proxmox ISO builder can create Proxmox VMs from ISO media, provision them, and store the result as a Proxmox image/template ([HashiCorp Packer Proxmox ISO builder](https://developer.hashicorp.com/packer/integrations/hashicorp/proxmox/latest/components/builder/iso)). OpenTofu or Terraform remains the VM declaration layer because the `bpg/proxmox` provider exposes Proxmox VE VM resources and clone-based VM creation ([bpg Proxmox provider VM resource](https://github.com/bpg/terraform-provider-proxmox/blob/main/docs/resources/virtual_environment_vm.md)). Ansible remains the guest configuration layer because it can manage Windows over WinRM using the `winrm` or `psrp` connection plugins, as long as the Windows guest has a WinRM listener configured first ([Ansible Windows Remote Management docs](https://docs.ansible.com/projects/ansible/latest/os_guide/windows_winrm.html)).

## What changes from the VM-based flow

Remove these steps:

- Creating a separate automation VM.
- Installing Packer directly on Linux.
- Installing OpenTofu directly on Linux.
- Installing Ansible and Python WinRM dependencies directly on Linux.

Replace them with:

- A Git repo mounted into containers.
- A Portainer stack that defines Packer, OpenTofu, and Ansible services.
- Named Docker volumes for plugin/cache persistence.
- One-shot container runs from the Portainer UI, Portainer console, or Docker CLI on the existing Docker host.

## Important Portainer design choice

For Portainer stacks, the simplest reliable model is to use **prebuilt images** rather than Compose `build:` blocks. Portainer can deploy Compose stacks easily, but image build behavior depends on how the stack is deployed and whether the Docker host has access to the build context. To avoid that friction:

- Use `hashicorp/packer` for Packer.
- Use `ghcr.io/opentofu/opentofu` for OpenTofu.
- Build or publish a small custom Ansible image once, or use a persistent Ansible utility container that installs dependencies on first start.

The cleaner long-term approach is a custom Ansible image with `ansible`, `pywinrm`, `pypsrp`, `requests-credssp`, and Windows collections preinstalled.

## Phase 1: Prepare the IaC repo

Create a Git repo that your Docker host can access. This can live:

- On the Docker host filesystem.
- In a private GitHub repo pulled by Portainer’s Git stack feature.
- In a bind-mounted path such as `/opt/stacks/proxmox-win11-iac`.

Recommended repo layout:

```text
proxmox-win11-dev-iac/
├── docker-compose.yml
├── .env
├── .env.example
├── packer/
│   ├── win11.pkr.hcl
│   ├── answer/
│   │   └── Autounattend.xml
│   └── scripts/
│       ├── bootstrap-winrm.ps1
│       ├── install-virtio.ps1
│       ├── install-qemu-agent.ps1
│       ├── baseline-windows.ps1
│       └── sysprep.ps1
├── tofu/
│   ├── providers.tf
│   ├── variables.tf
│   └── win11-dev.tf
└── ansible/
    ├── inventory/
    │   └── hosts.yml
    ├── group_vars/
    │   └── windows/
    │       └── vars.yml
    └── playbooks/
        └── win11-dev.yml
```

Add a `.gitignore`:

```gitignore
.env
*.auto.tfvars
*.tfstate
*.tfstate.*
.terraform/
.terraform.lock.hcl
crash.log
*.log
*.pkrvars.hcl
```

`*.pkrvars.hcl` remains ignored so old local Packer var files are never committed by mistake. Configuration values are listed in `.env.example`; at runtime they come from **Portainer stack Environment** and/or an optional **`.env` file on the Docker host**.

## Phase 2: Create the Portainer stack

In Portainer:

1. Go to **Stacks**.
2. Select **Add stack**.
3. Name it `proxmox-win11-iac`.
4. Choose either **Web editor** or **Git repository**.
5. If using Git, point Portainer at the repo containing this Compose file.
6. **Environment:** for **Git-based stacks**, paste every variable from `.env.example` into the stack **Environment** section (key/value). Uploading a dotenv in the UI **does not** create `.../proxmox-iac/.env` on the server filesystem; Compose resolves `env_file` paths on the host. Use **Environment**, or SSH to the host and create `.env` beside the compose checkout if you want a file.
7. Deploy the stack.

### Compose file

Use the repository root **`docker-compose.yml`** as-is. Each service uses optional **`env_file`** (`required: false`) **and** an explicit **`environment`** block that passes **`${VAR}`** through from Portainer stack Environment / host `.env`. That passthrough is required so variables reach containers (stack UI variables alone are not merged automatically).

Abbreviated pattern:

```yaml
packer:
  env_file:
    - path: .env
      required: false
  environment:
    PACKER_LOG: "1"
    TF_VAR_proxmox_api_token: ${TF_VAR_proxmox_api_token}
    WINRM_PASSWORD: ${WINRM_PASSWORD}
    PKR_VAR_proxmox_url: ${PKR_VAR_proxmox_url}
    # …all PKR_VAR_* keys from `.env.example`
```

```yaml
tofu:
  environment:
    TF_VAR_proxmox_endpoint: ${TF_VAR_proxmox_endpoint}
    TF_VAR_proxmox_api_token: ${TF_VAR_proxmox_api_token}
    # …remaining TF_VAR_* from `.env.example`
```

```yaml
ansible:
  environment:
    WINDOWS_ADMIN_PASSWORD: ${WINDOWS_ADMIN_PASSWORD}
```

### Better Ansible image option

The `cytopia/ansible` image is convenient, but for long-term repeatability you should build and publish your own Ansible image. Example `Dockerfile`:

```dockerfile
FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ssh \
    krb5-user \
    gcc \
    python3-dev \
    libkrb5-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
    ansible \
    pywinrm \
    pypsrp \
    requests-credssp

RUN ansible-galaxy collection install \
    ansible.windows \
    community.windows

WORKDIR /workspace
```

Build and push it from any Docker-capable system:

```bash
docker build -t registry.example.internal/ansible-windows:latest .
docker push registry.example.internal/ansible-windows:latest
```

Then replace the Ansible service image:

```yaml
image: registry.example.internal/ansible-windows:latest
```

## Phase 3: Configure stack environment variables

Maintain **one** list of variables (copy from `.env.example`): put them in **Portainer stack Environment** and/or in a host `.env` file beside the compose checkout. `docker-compose.yml` uses optional `env_file` (`required: false`) plus stack env; do not create separate `terraform.tfvars` or `*.pkrvars.hcl`.

For a **stack deployed from Git**, you normally **omit** `IAC_REPO_PATH` and `SSH_KEY_PATH` (workspace bind uses the checkout path; API-token auth for Proxmox). Portainer does not commit `.env`; create it on the Docker host beside the stack or paste the same keys into the stack environment UI.

OpenTofu uses `**TF_VAR_*`**. Packer reads `**PKR_VAR_<name>**` for each template variable (HashiCorp convention). `**TF_VAR_proxmox_api_token**` is reused as the Packer API token via `win11.pkr.hcl`. `**WINRM_PASSWORD**` / `**WINDOWS_ADMIN_PASSWORD**` stay plain keys.

See `**.env.example**` in the repo for the authoritative list. Abbreviated:

```bash
TF_VAR_proxmox_endpoint=https://pve01.example.internal:8006/
TF_VAR_proxmox_api_token=terraform@pve!iac=REDACTED
TF_VAR_proxmox_node=pve01
TF_VAR_datastore=local-lvm
TF_VAR_win11_template_id=9025
TF_VAR_vm_id=1101
TF_VAR_vm_name=win11-dev-01
TF_VAR_bridge=vmbr0

PKR_VAR_proxmox_url=https://pve01.example.internal:8006/api2/json
PKR_VAR_proxmox_node=pve01
PKR_VAR_proxmox_username=terraform@pve
PKR_VAR_template_vm_id=9025
PKR_VAR_template_name=tpl-win11-25h2-dev
PKR_VAR_iso_file=local:iso/Win11_25H2_English_x64.iso
PKR_VAR_virtio_iso_file=local:iso/virtio-win.iso
PKR_VAR_vm_storage=local-lvm
PKR_VAR_iso_storage=local
PKR_VAR_bridge=vmbr0
PKR_VAR_winrm_username=packer

WINRM_PASSWORD=REDACTED
WINDOWS_ADMIN_PASSWORD=REDACTED
```

## Phase 4: Prepare Proxmox

Upload these ISOs to your Proxmox ISO datastore:

```text
local:iso/Win11_25H2_English_x64.iso
local:iso/virtio-win.iso
```

Windows does not include native VirtIO support, so the VirtIO ISO supplies the signed drivers needed for paravirtualized disk and network devices ([Proxmox Windows VirtIO Drivers](https://pve.proxmox.com/wiki/Windows_VirtIO_Drivers)). Windows 11 also expects UEFI/Secure Boot capability and TPM 2.0 as part of Microsoft’s listed Windows 11 requirements ([Microsoft Windows 11 requirements](https://support.microsoft.com/en-us/windows/windows-11-system-requirements-86c11283-ea52-4782-9efd-7674389a7ba3)).

Create a dedicated Proxmox API token, for example:

```text
User:  terraform@pve
Token: terraform@pve!iac
```

Start broad while testing if needed, then reduce permissions after the workflow works.

## Phase 5: Create the Packer files

### Packer variables

Set `**PKR_VAR_***` and passwords in the **repo root `.env`** (see Phase 3). Packer does not use a separate `*.pkrvars.hcl` file. The `proxmox_token` variable defaults to `**TF_VAR_proxmox_api_token**`; `winrm_password` defaults to `**WINRM_PASSWORD**`.

### Packer HCL skeleton

Create `packer/win11.pkr.hcl`:

```hcl
packer {
  required_plugins {
    proxmox = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "proxmox_url"      { type = string }
variable "proxmox_node"     { type = string }
variable "proxmox_username" { type = string }
variable "proxmox_token"    { type = string, sensitive = true, default = env("TF_VAR_proxmox_api_token") }
variable "template_vm_id"   { type = number }
variable "template_name"    { type = string }
variable "iso_file"         { type = string }
variable "virtio_iso_file"  { type = string }
variable "vm_storage"       { type = string }
variable "iso_storage"      { type = string }
variable "bridge"           { type = string }
variable "winrm_username"   { type = string }
variable "winrm_password"   { type = string, sensitive = true, default = env("WINRM_PASSWORD") }

source "proxmox-iso" "win11" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  insecure_skip_tls_verify = true

  node                     = var.proxmox_node
  vm_id                    = var.template_vm_id
  vm_name                  = var.template_name
  template_name            = var.template_name

  iso_file                 = var.iso_file
  unmount_iso              = true

  qemu_agent               = true
  os                       = "win11"
  machine                  = "q35"
  bios                     = "ovmf"

  cores                    = 4
  memory                   = 8192
  scsi_controller          = "virtio-scsi-single"

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
```

Validate exact attribute names against your installed Packer Proxmox plugin version. The key intent is to build a Windows 11 template with OVMF, q35, VirtIO SCSI, VirtIO NIC, WinRM for provisioning, and QEMU guest agent support.

## Phase 6: Add Windows bootstrap scripts

Create `packer/scripts/bootstrap-winrm.ps1`:

```powershell
Set-ExecutionPolicy Bypass -Scope LocalMachine -Force

Enable-PSRemoting -Force
Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true
Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $true

New-NetFirewallRule `
  -DisplayName "Allow WinRM HTTP" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 5985 `
  -Action Allow

winrm quickconfig -quiet
```

Create `packer/scripts/install-virtio.ps1`:

```powershell
$ErrorActionPreference = "Stop"

$virtioDrive = Get-Volume |
  Where-Object { $_.FileSystemLabel -match "virtio|VirtIO" } |
  Select-Object -First 1

if (-not $virtioDrive) {
  throw "VirtIO ISO not found"
}

$drive = "$($virtioDrive.DriveLetter):"

$drivers = Get-ChildItem -Path $drive -Recurse -Filter "*.inf"
foreach ($driver in $drivers) {
  pnputil.exe /add-driver $driver.FullName /install | Out-Host
}
```

Create `packer/scripts/install-qemu-agent.ps1`:

```powershell
$ErrorActionPreference = "Stop"

$virtioDrive = Get-Volume |
  Where-Object { $_.FileSystemLabel -match "virtio|VirtIO" } |
  Select-Object -First 1

if (-not $virtioDrive) {
  throw "VirtIO ISO not found"
}

$drive = "$($virtioDrive.DriveLetter):"
$agent = Get-ChildItem -Path $drive -Recurse -Filter "qemu-ga-x86_64.msi" | Select-Object -First 1

if (-not $agent) {
  throw "QEMU guest agent installer not found"
}

Start-Process msiexec.exe -ArgumentList "/i `"$($agent.FullName)`" /qn /norestart" -Wait
Set-Service QEMU-GA -StartupType Automatic
Start-Service QEMU-GA
```

Proxmox uses the QEMU guest agent for cleaner shutdowns, filesystem freeze/thaw during backups, and reporting guest network information ([Proxmox QEMU guest agent docs](https://pve.proxmox.com/wiki/Qemu-guest-agent)).

Create `packer/scripts/baseline-windows.ps1`:

```powershell
$ErrorActionPreference = "Stop"

powercfg /hibernate off
powercfg /change standby-timeout-ac 0
powercfg /change monitor-timeout-ac 15
powercfg /setactive SCHEME_MIN

Set-ItemProperty `
  -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
  -Name "fDenyTSConnections" `
  -Value 0

Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

Set-ItemProperty `
  -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" `
  -Name "UserAuthentication" `
  -Value 1

New-ItemProperty `
  -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations" `
  -Name "DWMFRAMEINTERVAL" `
  -PropertyType DWord `
  -Value 15 `
  -Force
```

Microsoft documents `DWMFRAMEINTERVAL` under `HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations` with decimal value `15` as a workaround for raising some remote-session frame rates up to 60 FPS, but it can increase bandwidth and remote-host resource usage ([Microsoft RDP frame rate guidance](https://learn.microsoft.com/en-us/troubleshoot/windows-server/remote/frame-rate-limited-to-30-fps)).

Create `packer/scripts/sysprep.ps1`:

```powershell
$ErrorActionPreference = "Stop"

Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

Start-Process `
  -FilePath "$env:SystemRoot\System32\Sysprep\Sysprep.exe" `
  -ArgumentList "/generalize /oobe /shutdown /quiet" `
  -Wait
```

## Phase 7: Run Packer from Portainer

From Portainer:

1. Open the `proxmox-win11-iac` stack.
2. Open the `iac-packer` container.
3. Use **Console**.
4. Start `/bin/sh`.

Run:

```bash
cd /workspace/packer
packer init .
packer validate win11.pkr.hcl
packer build win11.pkr.hcl
```

Alternative from the Docker host shell:

```bash
docker exec -it iac-packer sh
cd /workspace/packer
packer init .
packer validate win11.pkr.hcl
packer build win11.pkr.hcl
```

At the end, Proxmox should have a template such as:

```text
tpl-win11-25h2-dev
```

## Phase 8: Create OpenTofu config

Create `tofu/providers.tf`:

```hcl
terraform {
  required_version = ">= 1.8.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.70"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true

  ssh {
    agent    = false
    username = var.proxmox_ssh_user
  }
}
```

Create `tofu/variables.tf`:

```hcl
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
```

Create `tofu/win11-dev.tf`:

```hcl
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
```

## Phase 9: Run OpenTofu from Portainer

From Portainer:

1. Open the `iac-tofu` container.
2. Open **Console**.
3. Start `/bin/sh`.

Run:

```bash
cd /workspace/tofu
tofu init
tofu fmt
tofu validate
tofu plan
tofu apply
```

Alternative from the Docker host shell:

```bash
docker exec -it iac-tofu sh
cd /workspace/tofu
tofu init
tofu fmt
tofu validate
tofu plan
tofu apply
```

## Phase 10: Configure Ansible

Create `ansible/inventory/hosts.yml`:

```yaml
all:
  children:
    windows:
      hosts:
        win11-dev-01:
          ansible_host: 192.168.10.51
```

Create `ansible/group_vars/windows/vars.yml`:

```yaml
ansible_user: devadmin
ansible_password: "{{ lookup('env', 'WINDOWS_ADMIN_PASSWORD') | mandatory }}"
ansible_connection: winrm
ansible_winrm_transport: basic
ansible_winrm_server_cert_validation: ignore
ansible_port: 5985
```

Set `**WINDOWS_ADMIN_PASSWORD**` in the same repo root `.env` as the stack (see `.env.example`). The `iac-ansible` service passes it into the container.

Create `ansible/playbooks/win11-dev.yml`:

```yaml
---
- name: Configure Windows 11 dev workstation
  hosts: windows
  gather_facts: false

  tasks:
    - name: Ensure RDP is enabled
      ansible.windows.win_regedit:
        path: HKLM:\System\CurrentControlSet\Control\Terminal Server
        name: fDenyTSConnections
        data: 0
        type: dword

    - name: Ensure RDP firewall rule is enabled
      ansible.windows.win_firewall_rule:
        group: Remote Desktop
        enabled: true

    - name: Disable hibernation
      ansible.windows.win_command: powercfg /hibernate off

    - name: Install PowerShell 7
      ansible.windows.win_powershell:
        script: |
          winget install --id Microsoft.PowerShell --silent --accept-source-agreements --accept-package-agreements

    - name: Install Git
      ansible.windows.win_powershell:
        script: |
          winget install --id Git.Git --silent --accept-source-agreements --accept-package-agreements

    - name: Install VS Code
      ansible.windows.win_powershell:
        script: |
          winget install --id Microsoft.VisualStudioCode --silent --accept-source-agreements --accept-package-agreements
```

## Phase 11: Run Ansible from Portainer

From Portainer:

1. Open the `iac-ansible` container.
2. Open **Console**.
3. Start `/bin/sh`.

Run:

```bash
cd /workspace/ansible
ansible -i inventory/hosts.yml windows -m ansible.windows.win_ping
ansible-playbook -i inventory/hosts.yml playbooks/win11-dev.yml
```

Alternative from the Docker host shell:

```bash
docker exec -it iac-ansible sh
cd /workspace/ansible
ansible -i inventory/hosts.yml windows -m ansible.windows.win_ping
ansible-playbook -i inventory/hosts.yml playbooks/win11-dev.yml
```

## Phase 12: Future Windows ISO upgrades

Keep Packer builds versioned by updating `**PKR_VAR_***` and `**TF_VAR_***` in `.env` (e.g. new template ID, ISO name):

```bash
PKR_VAR_template_vm_id=9026
PKR_VAR_template_name=tpl-win11-26h2-dev
PKR_VAR_iso_file=local:iso/Win11_26H2_English_x64.iso
PKR_VAR_virtio_iso_file=local:iso/virtio-win.iso
```

Run from the Packer container:

```bash
cd /workspace/packer
packer build win11.pkr.hcl
```

Then align OpenTofu with the new template ID:

```bash
TF_VAR_win11_template_id=9026
```

Redeploy or recreate containers if needed so they reload `.env`, then run from the OpenTofu container:

```bash
cd /workspace/tofu
tofu plan
tofu apply
```

Keep old templates until the new template is validated. Rollback is just changing `TF_VAR_win11_template_id` back to the older template ID.

## Portainer-specific operating tips

- Use named volumes for Packer/OpenTofu caches so plugin downloads persist across restarts.
- If you use Portainer Git stacks, make sure stack redeploys do not overwrite local secret files.
- Keep `.env`, tfstate, and any local override files that contain secrets out of Git.
- If the containers need to trust your internal Proxmox certificate, bake your internal CA into custom images or mount it and update the CA store.
- If DNS inside containers cannot resolve `pve01.example.internal`, either fix Docker host DNS or use the Proxmox IP in variables.
- Avoid exposing WinRM or RDP outside your trusted LAN/VPN.
- Prefer immutable Windows templates by version instead of overwriting a known-good template.

## Minimal Portainer workflow recap

1. Put the IaC repo on your Docker host or in Git.
2. Create a Portainer stack named `proxmox-win11-iac`.
3. Paste or reference the Compose file.
4. Add Proxmox/OpenTofu environment variables.
5. Deploy the stack.
6. Open the Packer container console and run:

```bash
cd /workspace/packer
packer init .
packer validate win11.pkr.hcl
packer build win11.pkr.hcl
```

1. Open the OpenTofu container console and run:

```bash
cd /workspace/tofu
tofu init
tofu plan
tofu apply
```

1. Open the Ansible container console and run:

```bash
cd /workspace/ansible
ansible -i inventory/hosts.yml windows -m ansible.windows.win_ping
ansible-playbook -i inventory/hosts.yml playbooks/win11-dev.yml
```

