#!/bin/sh
# Renders answer/Autounattend.in.xml → answer/Autounattend.xml
#   __WIM_META_*           ← PKR_VAR_win11_install_wim_index OR PKR_VAR_win11_install_image_name (overrides index)
#   __INSTALL_FILENAME__   ← PKR_VAR_win11_install_filename (default install.wim; install.esd for some retail ISOs)
#   __WINRM_PASSWORD__     ← WINRM_PASSWORD (same as Packer winrm_password)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IDX="${PKR_VAR_win11_install_wim_index:-6}"
INSTFN="${PKR_VAR_win11_install_filename:-install.wim}"
: "${WINRM_PASSWORD:?WINRM_PASSWORD must be set (same as Packer winrm_password)}"

MK="/IMAGE/INDEX"
MV="$IDX"
META_MODE="index"
if [ -n "${PKR_VAR_win11_install_image_name:-}" ]; then
  MK="/IMAGE/NAME"
  MV="$PKR_VAR_win11_install_image_name"
  META_MODE="name"
fi

# awk: gsub replacement treats & specially; escape \ and & in the password and meta value
awk -v mk="$MK" -v mv="$MV" -v instfn="$INSTFN" -v pw="$WINRM_PASSWORD" '
function esc_repl(s, r) {
  r = s
  gsub(/\\/, "\\\\", r)
  gsub(/&/, "\\&", r)
  return r
}
{
  gsub(/__WIM_META_KEY__/, mk)
  gsub(/__WIM_META_VALUE__/, esc_repl(mv))
  gsub(/__INSTALL_FILENAME__/, instfn)
  gsub(/__WINRM_PASSWORD__/, esc_repl(pw))
  print
}' "$ROOT/answer/Autounattend.in.xml" > "$ROOT/answer/Autounattend.xml"

if grep -qE '__WIM_META_KEY__|__WIM_META_VALUE__|__INSTALL_FILENAME__|__WINRM_PASSWORD__' "$ROOT/answer/Autounattend.xml"; then
  echo "FATAL: render left placeholders in Autounattend.xml"
  exit 1
fi

if [ "$META_MODE" = "name" ]; then
  echo "Rendered Autounattend.xml with /IMAGE/NAME from PKR_VAR_win11_install_image_name"
else
  echo "Rendered Autounattend.xml with /IMAGE/INDEX=$IDX"
fi

# #region agent log
REPO="$(cd "$ROOT/.." && pwd)"
LOG="$REPO/debug-d29db6.log"
OUT="$ROOT/answer/Autounattend.xml"
PATH_LINE=$(grep -E 'install\.(wim|esd)' "$OUT" | head -1 | sed -n 's/.*<Path>//;s|</Path>.*||p' | tr -d '\r')
LEAK=0
grep -q '__WIM_META_KEY__\|__WIM_META_VALUE__\|__WINRM_PASSWORD__\|__INSTALL_FILENAME__' "$OUT" 2>/dev/null && LEAK=1 || true
KIND="other"
case "$PATH_LINE" in
  *install.esd) KIND="esd" ;;
  *install.wim) KIND="wim" ;;
esac
TS_MS=$(( $(date +%s) * 1000 ))
BOM=0
if command -v od >/dev/null 2>&1; then
  FIRST=$(od -An -tx1 -N3 "$OUT" 2>/dev/null | tr -d ' \n')
  case "$FIRST" in efbbbf|EFBBBF) BOM=1 ;; esac
fi
REP=0
grep -q '<Value>REPLACE_ME</Value>' "$OUT" 2>/dev/null && REP=1 || true
printf '{"sessionId":"d29db6","hypothesisId":"H1-H6","location":"render-autounattend.sh","message":"Autounattend rendered","data":{"installMediaKind":"%s","installFilename":"%s","renderedIndex":"%s","installImageMetaMode":"%s","placeholderLeak":%s,"utf8BomPresent":%s,"repoReplaceMePasswordStillPresent":%s},"timestamp":%s}\n' \
  "$KIND" "$INSTFN" "$IDX" "$META_MODE" "$LEAK" "$BOM" "$REP" "$TS_MS" >>"$LOG" || true
# #endregion
