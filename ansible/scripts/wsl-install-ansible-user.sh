#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
if ! python3 -m pip --version >/dev/null 2>&1; then
  curl -sS https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py
  python3 /tmp/get-pip.py --user --break-system-packages
fi
export PATH="$HOME/.local/bin:$PATH"
python3 -m pip install --user --break-system-packages "ansible-core>=2.15,<2.17"
ansible-playbook --version | head -1
