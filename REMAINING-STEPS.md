# Remaining steps (your environment)

The IaC files in this repo are in place. What follows is what **you** still do on your machine and infrastructure to finish the Proxmox → Windows 11 dev VM workflow. Detailed commands live in [proxmox-win11-iac-portainer-runbook.md](proxmox-win11-iac-portainer-runbook.md); use this as a checklist.

---

## 1. Repository and Git (optional)

- Push or clone this repo somewhere your **Docker host** can read (filesystem bind mount, or Portainer Git stack).
- If you use GitHub from this PC: install GitHub CLI (`winget install GitHub.cli`) and run **`gh auth login`** in **your** terminal (interactive browser login).

---

## 2. Local secrets and copies (do not commit)

| Template | Create locally |
|----------|----------------|
| `.env.example` | `.env` on the Docker host with real `PROXMOX_*`, `TF_VAR_*`, `IAC_REPO_PATH`, `SSH_KEY_PATH` |
| `packer/vars-25h2.pkrvars.hcl.example` | `packer/vars-25h2.pkrvars.hcl` (real Proxmox token, ISO paths, `winrm_password`, template ID/name) |
| `tofu/terraform.tfvars.example` | `tofu/terraform.tfvars` (or set equivalent `TF_VAR_*` in the stack env) |
| `ansible/group_vars/windows/vault.yml.example` | `ansible/group_vars/windows/vault.yml` then `ansible-vault encrypt` on that file |

`.gitignore` already excludes `.env`, `*.pkrvars.hcl`, and `vault.yml`.

---

## 3. Proxmox preparation (runbook Phase 4)

- Upload **Windows 11** and **virtio-win** ISOs to the ISO storage you reference in Packer vars (names must match `iso_file` / `virtio_iso_file`).
- Create a **Proxmox API token** (e.g. `terraform@pve!iac=...`) and use it consistently in Packer, OpenTofu stack env, and any local var files.
- Tighten token permissions after the first successful end-to-end run.

---

## 4. Unattend and template alignment

- In `packer/answer/Autounattend.xml`, the **Windows image name** under `InstallFrom` / `MetaData` must match your ISO (e.g. `dism /Get-WimInfo` on the mounted ISO). The repo default targets **Windows 11 Pro**; change if your media is different.
- Keep the **local `packer` user password** in `Autounattend.xml` in sync with **`winrm_password`** in your Packer vars file.
- After Packer finishes, note the **template VM ID and name**; they must match **`TF_VAR_win11_template_id`** (and your Terraform/OpenTofu variables).

---

## 5. Portainer stack (runbook Phases 2–3)

- Deploy the Compose stack (e.g. name **`proxmox-win11-iac`**) so containers **`iac-packer`**, **`iac-tofu`**, **`iac-ansible`** can reach the repo at **`IAC_REPO_PATH`** (or equivalent mount).
- Ensure stack environment variables match `.env.example` for your cluster (bridge, datastore, node, VM IDs, names).
- Optional: build **`Dockerfile.ansible`**, push to your registry, then switch the `ansible` service `image:` in `docker-compose.yml` as commented in the file.

---

## 6. Run Packer (runbook Phase 7)

From the **`iac-packer`** container console (or `docker exec`):

```bash
cd /workspace/packer
packer init .
packer validate -var-file=vars-25h2.pkrvars.hcl win11.pkr.hcl
packer build -var-file=vars-25h2.pkrvars.hcl win11.pkr.hcl
```

Confirm the Windows template exists in Proxmox before continuing.

---

## 7. Run OpenTofu (runbook Phase 9)

From **`iac-tofu`**:

```bash
cd /workspace/tofu
tofu init
tofu fmt
tofu validate
tofu plan
tofu apply
```

Ensure **`win11_template_id`** matches the Packer-built template.

---

## 8. Ansible inventory and guest access (runbook Phases 10–11)

- Set **`ansible_host`** in `ansible/inventory/hosts.yml` to the **live IP** of the cloned VM.
- The playbook assumes a Windows admin account **`devadmin`** with the password in the vault; create that user on the guest (or adjust **`ansible_user`** / automation account) so WinRM matches what you configured after clone/sysprep.
- From **`iac-ansible`**:

```bash
cd /workspace/ansible
ansible-galaxy collection install ansible.windows community.windows   # if not baked into image
ansible -i inventory/hosts.yml windows -m ansible.windows.win_ping --ask-vault-pass
ansible-playbook -i inventory/hosts.yml playbooks/win11-dev.yml --ask-vault-pass
```

`winget` tasks need network and Microsoft Store access on the guest; allow retries if the store is slow.

---

## 9. Validate playbooks on your workstation (optional)

- **Ansible is not supported as a controller on native Windows** for current ansible-core (Unix-only modules). Use the **`iac-ansible`** container, or **WSL (Ubuntu)**.
- In WSL, you can run:

  ```bash
  bash /mnt/c/Users/KrisPennington/Downloads/ansible/ansible/scripts/wsl-syntax-check.sh
  ```

  (Adjust the path if your repo lives elsewhere.) First-time Ubuntu setup may require **`sudo apt install ansible`** or the user-space script **`ansible/scripts/wsl-install-ansible-user.sh`** if you avoid `sudo`.

- If **Intune Attack Surface Reduction** blocks Python/Ansible, add an exclusion for your dev tools as you did before.

---

## 10. UTF-8 on Windows (only if you insist on PowerShell Ansible)

If you ever run Ansible directly on Windows and hit **“locale encoding must be UTF-8”**, enable **Settings → Time & language → Language & region → Administrative language settings → Change system locale → Beta: Use Unicode UTF-8 for worldwide language support**, then reboot. Prefer Linux/WSL or the container for Ansible regardless.

---

## 11. Later: new Windows ISO (runbook Phase 12)

When you adopt a new ISO: copy/new Packer vars (`template_vm_id`, `template_name`, `iso_file`), rebuild with Packer, update **`TF_VAR_win11_template_id`**, then `tofu plan` / `tofu apply`.

---

## Quick dependency graph

```text
Secrets (.env, pkrvars, tfvars, vault)
       → Proxmox ISOs + API token
       → Portainer stack (mounted repo)
       → Packer build (template)
       → OpenTofu apply (clone VM)
       → Ansible (guest config)
```

When all steps succeed, your Windows 11 dev VM should match the template plus Ansible-driven software (RDP, PowerShell 7, Git, VS Code per the playbook).
