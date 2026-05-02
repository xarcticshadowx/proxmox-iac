#!/bin/sh
# Renders answer/Autounattend.in.xml → answer/Autounattend.xml
#   __PKR_WIM_INDEX__      ← PKR_VAR_win11_install_wim_index (default 6)
#   __INSTALL_FILENAME__   ← PKR_VAR_win11_install_filename (default install.wim; install.esd for some retail ISOs)
#   __WINRM_PASSWORD__     ← WINRM_PASSWORD (same as Packer winrm_password)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IDX="${PKR_VAR_win11_install_wim_index:-6}"
INSTFN="${PKR_VAR_win11_install_filename:-install.wim}"
: "${WINRM_PASSWORD:?WINRM_PASSWORD must be set (same as Packer winrm_password)}"

# awk: gsub replacement treats & specially; escape \ and & in the password
awk -v idx="$IDX" -v instfn="$INSTFN" -v pw="$WINRM_PASSWORD" '
function esc_repl(s, r) {
  r = s
  gsub(/\\/, "\\\\", r)
  gsub(/&/, "\\&", r)
  return r
}
{
  gsub(/__PKR_WIM_INDEX__/, idx)
  gsub(/__INSTALL_FILENAME__/, instfn)
  gsub(/__WINRM_PASSWORD__/, esc_repl(pw))
  print
}' "$ROOT/answer/Autounattend.in.xml" > "$ROOT/answer/Autounattend.xml"

echo "Rendered Autounattend.xml with /IMAGE/INDEX=$IDX"

# #region agent log
REPO="$(cd "$ROOT/.." && pwd)"
LOG="$REPO/debug-d29db6.log"
OUT="$ROOT/answer/Autounattend.xml"
PATH_LINE=$(grep -E 'install\.(wim|esd)' "$OUT" | head -1 | sed -n 's/.*<Path>//;s|</Path>.*||p' | tr -d '\r')
LEAK=0
grep -q '__PKR_WIM_INDEX__\|__WINRM_PASSWORD__\|__INSTALL_FILENAME__' "$OUT" 2>/dev/null && LEAK=1 || true
KIND="other"
case "$PATH_LINE" in
  *install.esd) KIND="esd" ;;
  *install.wim) KIND="wim" ;;
esac
TS_MS=$(( $(date +%s) * 1000 ))
printf '{"sessionId":"d29db6","hypothesisId":"H1-H4","location":"render-autounattend.sh","message":"Autounattend rendered (host)","data":{"installMediaKind":"%s","installFilename":"%s","renderedIndex":"%s","placeholderLeak":%s},"timestamp":%s}\n' \
  "$KIND" "$INSTFN" "$IDX" "$LEAK" "$TS_MS" >>"$LOG" || true
# #endregion
