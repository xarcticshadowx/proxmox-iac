#!/usr/bin/env bash
# Run from Ubuntu/WSL after cd to this ansible dir:
#   bash scripts/wsl-syntax-check.sh
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT}"

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "Installing ansible (requires sudo once for apt)..."
  sudo apt-get update -qq
  sudo apt-get install -y ansible
fi

ansible-galaxy collection install ansible.windows community.windows

ansible-playbook -i inventory/hosts.yml playbooks/win11-dev.yml --syntax-check
echo "syntax-check: OK"
