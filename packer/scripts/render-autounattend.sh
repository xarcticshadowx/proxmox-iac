#!/bin/sh
# Renders answer/Autounattend.in.xml → answer/Autounattend.xml
#   __PKR_WIM_INDEX__  ← PKR_VAR_win11_install_wim_index (default 6)
#   __WINRM_PASSWORD__ ← WINRM_PASSWORD (same as Packer winrm_password)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IDX="${PKR_VAR_win11_install_wim_index:-6}"
: "${WINRM_PASSWORD:?WINRM_PASSWORD must be set (same as Packer winrm_password)}"

# awk: gsub replacement treats & specially; escape \ and & in the password
awk -v idx="$IDX" -v pw="$WINRM_PASSWORD" '
function esc_repl(s, r) {
  r = s
  gsub(/\\/, "\\\\", r)
  gsub(/&/, "\\&", r)
  return r
}
{
  gsub(/__PKR_WIM_INDEX__/, idx)
  gsub(/__WINRM_PASSWORD__/, esc_repl(pw))
  print
}' "$ROOT/answer/Autounattend.in.xml" > "$ROOT/answer/Autounattend.xml"

echo "Rendered Autounattend.xml with /IMAGE/INDEX=$IDX"
