#!/bin/sh
# Run from repo after env is loaded (same WINRM_PASSWORD / PKR_VAR_* as Packer).
# Usage (iac-packer container): cd /workspace/packer && sh scripts/packer-build-with-render.sh [packer build args...]
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
PACKER_DIR="$(cd "$HERE/.." && pwd)"
sh "$HERE/render-autounattend.sh"
cd "$PACKER_DIR"
exec packer build "$@"
