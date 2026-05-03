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
  echo "WARN: PKR_VAR_win11_install_image_name is set — must match dism /Get-WimInfo Name exactly or Setup fails. If index ${IDX} is correct, unset PKR_VAR_win11_install_image_name." >&2
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
# Session debug: H1 wrong WIM index/name, H2 install.wim vs install.esd, H3 virtio vioscsi path, H4 Dynamic Update, H5 name typo
REPO="$(cd "$ROOT/.." && pwd)"
LOG="$REPO/debug-932ce5.log"
OUT="$ROOT/answer/Autounattend.xml"
PATH_LINE=$(sed -n '/<InstallFrom>/,/<\/InstallFrom>/p' "$OUT" | grep '<Path>' | head -1 | sed -n 's/.*<Path>//;s|</Path>.*||p' | tr -d '\r')
META_KEY_LINE=$(sed -n '/<InstallFrom>/,/<\/InstallFrom>/p' "$OUT" | grep '<Key>' | head -1 | sed -n 's/.*<Key>//;s|</Key>.*||p' | tr -d '\r')
META_VAL_LINE=$(sed -n '/<InstallFrom>/,/<\/InstallFrom>/p' "$OUT" | grep '<Value>' | head -1 | sed -n 's/.*<Value>//;s|</Value>.*||p' | tr -d '\r')
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
VIRTIO=0
grep -q 'vioscsi.inf' "$OUT" 2>/dev/null && VIRTIO=1 || true
CLOUD_OFF=0
grep -q 'DisableCloudOptimizedContent' "$OUT" 2>/dev/null && CLOUD_OFF=1 || true
if command -v jq >/dev/null 2>&1; then
  jq -n --arg sid "932ce5" --arg hk "H1" --arg loc "render-autounattend.sh" \
    --arg mk "$META_KEY_LINE" --arg mv "$META_VAL_LINE" --arg mm "$META_MODE" --argjson ts "$TS_MS" \
    '{sessionId:$sid,hypothesisId:$hk,location:$loc,message:"InstallFrom MetaData (image selection)",data:{metaKey:$mk,metaValue:$mv,metaMode:$mm},timestamp:$ts}' >>"$LOG"
  jq -n --arg sid "932ce5" --arg hk "H2" --arg loc "render-autounattend.sh" \
    --arg p "$PATH_LINE" --arg instfn "$INSTFN" --arg kind "$KIND" --argjson ts "$TS_MS" \
    '{sessionId:$sid,hypothesisId:$hk,location:$loc,message:"InstallFrom Path vs env filename",data:{installFromPath:$p,pkrInstallFilename:$instfn,pathMediaKind:$kind},timestamp:$ts}' >>"$LOG"
  jq -n --arg sid "932ce5" --arg hk "H3" --arg loc "render-autounattend.sh" \
    --argjson virtio "$VIRTIO" --argjson ts "$TS_MS" \
    '{sessionId:$sid,hypothesisId:$hk,location:$loc,message:"VirtIO RunSynchronous references vioscsi.inf",data:{vioscsiInfReferenced:$virtio},timestamp:$ts}' >>"$LOG"
  jq -n --arg sid "932ce5" --arg hk "H4" --arg loc "render-autounattend.sh" \
    --argjson cloud "$CLOUD_OFF" --argjson leak "$LEAK" --argjson bom "$BOM" --argjson rep "$REP" --argjson ts "$TS_MS" \
    '{sessionId:$sid,hypothesisId:$hk,location:$loc,message:"Cloud-update mitigation + placeholder/BOM",data:{disableCloudOptimizedContentLinePresent:$cloud,placeholderLeak:$leak,utf8BomPresent:$bom,replaceMeStillPresent:$rep},timestamp:$ts}' >>"$LOG"
  NM_JSON=$( [ -n "${PKR_VAR_win11_install_image_name:-}" ] && echo true || echo false )
  jq -n --arg sid "932ce5" --arg hk "H5" --arg loc "render-autounattend.sh" \
    --arg idx "$IDX" --argjson nm "$NM_JSON" --argjson ts "$TS_MS" \
    '{sessionId:$sid,hypothesisId:$hk,location:$loc,message:"PKR_VAR defaults used at render",data:{pkrWin11InstallWimIndex:$idx,pkrWin11InstallImageNameSet:$nm},timestamp:$ts}' >>"$LOG"
else
  NAME_SET=0
  [ -n "${PKR_VAR_win11_install_image_name:-}" ] && NAME_SET=1
  printf '{"sessionId":"932ce5","hypothesisId":"H1","location":"render-autounattend.sh","message":"InstallFrom MetaData","data":{"metaKey":"%s","metaValue":"%s","metaMode":"%s"},"timestamp":%s}\n' \
    "$META_KEY_LINE" "$META_VAL_LINE" "$META_MODE" "$TS_MS" >>"$LOG" || true
  printf '{"sessionId":"932ce5","hypothesisId":"H2","location":"render-autounattend.sh","message":"InstallFrom Path","data":{"installFromPath":"%s","pkrInstallFilename":"%s","pathMediaKind":"%s"},"timestamp":%s}\n' \
    "$PATH_LINE" "$INSTFN" "$KIND" "$TS_MS" >>"$LOG" || true
  printf '{"sessionId":"932ce5","hypothesisId":"H3","location":"render-autounattend.sh","message":"VirtIO","data":{"vioscsiInfReferenced":%s},"timestamp":%s}\n' "$VIRTIO" "$TS_MS" >>"$LOG" || true
  printf '{"sessionId":"932ce5","hypothesisId":"H4","location":"render-autounattend.sh","message":"Mitigations","data":{"disableCloudOptimizedContentLinePresent":%s,"placeholderLeak":%s,"utf8BomPresent":%s,"replaceMeStillPresent":%s},"timestamp":%s}\n' \
    "$CLOUD_OFF" "$LEAK" "$BOM" "$REP" "$TS_MS" >>"$LOG" || true
  printf '{"sessionId":"932ce5","hypothesisId":"H5","location":"render-autounattend.sh","message":"PKR defaults","data":{"pkrWin11InstallWimIndex":"%s","pkrWin11InstallImageNameSet":%s},"timestamp":%s}\n' \
    "$IDX" "$NAME_SET" "$TS_MS" >>"$LOG" || true
fi
# #endregion
