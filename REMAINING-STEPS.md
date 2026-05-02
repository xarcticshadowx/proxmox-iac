# Remaining steps (your environment)

The IaC files in this repo are in place. What follows is what **you** still do on your machine and infrastructure to finish the Proxmox → Windows 11 dev VM workflow. Detailed commands live in [proxmox-win11-iac-portainer-runbook.md](proxmox-win11-iac-portainer-runbook.md); use this as a checklist.

---

## 1. Repository and Git (optional)

- Push or clone this repo somewhere your **Docker host** can read (filesystem bind mount, or Portainer Git stack).
- If you use GitHub from this PC: install GitHub CLI (`winget install GitHub.cli`) and run `**gh auth login`** in **your** terminal (interactive browser login).

---

## 2. Local configuration (do not commit)


| Template       | Create locally                                                                                                                                                                                                                                                                                                       |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.env.example` | Use every key in **Portainer → Stack → Environment** (best for Git stacks). Optionally also maintain a `**.env`** on the Docker host beside the compose file. Fill in all `TF_VAR_*`, `PKR_VAR_*`, `WINRM_PASSWORD`, and `WINDOWS_ADMIN_PASSWORD`. Omit `IAC_REPO_PATH` and `SSH_KEY_PATH` when applicable (see §5). |


`.gitignore` already excludes `.env` and `*.pkrvars.hcl` (legacy local files only).

---

## 3. Proxmox preparation (runbook Phase 4)

- Upload **Windows 11** and **virtio-win** ISOs to the ISO storage you reference in `**.env`** as `PKR_VAR_iso_file` / `PKR_VAR_virtio_iso_file`.
- Create a **Proxmox API token** (e.g. `terraform@pve!iac=...`) and set `**TF_VAR_proxmox_api_token`** in `.env` (Packer reuses it for `proxmox_token`).
- Tighten token permissions after the first successful end-to-end run.

---

## 4. Unattend and template alignment

- In `packer/answer/Autounattend.xml`, the **Windows image name** under `InstallFrom` / `MetaData` must match your ISO (e.g. `dism /Get-WimInfo` on the mounted ISO). The repo default targets **Windows 11 Pro**; change if your media is different.
- Keep the **local `packer` user password** in `Autounattend.xml` in sync with `**WINRM_PASSWORD`** in your repo root `.env`.
- After Packer finishes, note the **template VM ID and name**; they must match `**TF_VAR_win11_template_id`** (and your OpenTofu variables).

---

## 5. Portainer stack (runbook Phases 2–3)

**Volumes**

- `**/workspace`** — **bind mount only**: `${IAC_REPO_PATH:-.}` maps the **host repo directory** (cloned/checked-out files) into the containers. Nothing else is named here.
- **Named Docker volumes** (persist across restarts): `packer_cache`, `packer_plugins`, `tofu_cache`, `ansible_home` — Packer/OpenTofu/Ansible caches and Ansible’s `/root`, **not** your Git tree.

**Environment — Portainer stack from Git (usual case)**

- **Do not set `IAC_REPO_PATH` or `SSH_KEY_PATH`.** Compose uses `**.`** for the workspace bind, which is Portainer’s **Git checkout folder** on the Docker host, so `packer/`, `tofu/`, and `ansible/` appear under `/workspace`. Redeploys refresh the checkout; containers see updated files.
- **Do not set `SSH_KEY_PATH`** if Proxmox auth is **API token only** (typical for OpenTofu with this stack).

**When you would set them**

- `**IAC_REPO_PATH`** — only if the repo lives at a **fixed path** you manage yourself (not Portainer’s checkout), e.g. `/opt/stacks/proxmox-iac`.
- `**SSH_KEY_PATH`** — only if the OpenTofu provider must use a **host SSH private key** file (uncommon when using API tokens).

Configure every variable from `.env.example` in **Portainer → Stack → Environment** (recommended for Git stacks), and/or create a `**.env` file on the Docker host** next to the compose checkout. `**docker-compose.yml` passes each key via `environment: VAR: ${VAR}`** so Portainer substitutes stack variables into the containers (required for Packer `PKR_VAR_*`). Optional `**env_file`** still loads a host `.env` when present.

Optional: build `**Dockerfile.ansible`**, push to your registry, then switch the `ansible` service `image:` in `docker-compose.yml` as commented in the file.

---

## 6. Run Packer (runbook Phase 7)

From the `**iac-packer`** container console (or `docker exec`). Ensure **stack Environment** (or an optional host `.env`) defines all `PKR_VAR_`* and credentials.

```bash
cd /workspace/packer
packer init .
packer validate win11.pkr.hcl
packer build win11.pkr.hcl
```

Confirm the Windows template exists in Proxmox before continuing.

---

## 7. Run OpenTofu (runbook Phase 9)

From `**iac-tofu**`:

```bash
cd /workspace/tofu
tofu init
tofu fmt
tofu validate
tofu plan
tofu apply
```

Ensure `**win11_template_id**` matches the Packer-built template.

---

## 8. Ansible inventory and guest access (runbook Phases 10–11)

- Set `**ansible_host**` in `ansible/inventory/hosts.yml` to the **live IP** of the cloned VM.
- The playbook assumes a Windows admin account `**devadmin`** with the password in `**WINDOWS_ADMIN_PASSWORD`** (repo root `.env`); create that user on the guest (or adjust `**ansible_user`** / automation account) so WinRM matches what you configured after clone/sysprep.
- From `**iac-ansible`** (Compose loads `.env` via `env_file`):

```bash
cd /workspace/ansible
ansible-galaxy collection install ansible.windows community.windows   # if not baked into image
ansible -i inventory/hosts.yml windows -m ansible.windows.win_ping
ansible-playbook -i inventory/hosts.yml playbooks/win11-dev.yml
```

`winget` tasks need network and Microsoft Store access on the guest; allow retries if the store is slow.

---

## 9. Validate playbooks on your workstation (optional)

- **Ansible is not supported as a controller on native Windows** for current ansible-core (Unix-only modules). Use the `**iac-ansible`** container, or **WSL (Ubuntu)**.
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

When you adopt a new ISO: update `**PKR_VAR_*`** (template id/name, `iso_file`) in `.env`, rebuild with Packer, update `**TF_VAR_win11_template_id`**, then `tofu plan` / `tofu apply`.

---

## Quick dependency graph

```text
Repo `.env` (TF_VAR_*, PKR_VAR_*, passwords)
       → Proxmox ISOs + API token
       → Portainer stack (mounted repo)
       → Packer build (template)
       → OpenTofu apply (clone VM)
       → Ansible (guest config)
```

When all steps succeed, your Windows 11 dev VM should match the template plus Ansible-driven software (RDP, PowerShell 7, Git, VS Code per the playbook).