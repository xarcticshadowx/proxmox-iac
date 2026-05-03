#!/bin/sh
# Run from repo after env is loaded (same WINRM_PASSWORD / PKR_VAR_* as Packer).
# Usage (iac-packer container): cd /workspace/packer && sh scripts/packer-build-with-render.sh [packer build args...]
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
PACKER_DIR="$(cd "$HERE/.." && pwd)"
sh "$HERE/render-autounattend.sh"
cd "$PACKER_DIR"

# #region agent log
_AGENT_LOG="$(cd "$PACKER_DIR/.." && pwd)/debug-d3071e.log"
_TS="$(($(date +%s) * 1000))"
_SUP="${PKR_VAR_supplemental_iso_file:-}"
_ALLOW="${PKR_VAR_allow_build_without_supplemental_iso:-}"
if [ -n "$_SUP" ]; then _SLEN="$(printf '%s' "$_SUP" | wc -c | tr -d ' ')"; else _SLEN=0; fi
if [ -z "$_SUP" ]; then _SEMPTY=true; else _SEMPTY=false; fi
printf '%s\n' "{\"sessionId\":\"d3071e\",\"hypothesisId\":\"H1\",\"location\":\"packer-build-with-render.sh\",\"message\":\"PKR_VAR supplemental before packer build\",\"data\":{\"supplementalEmpty\":$_SEMPTY,\"supplementalLen\":$_SLEN,\"allowBuildWithoutSupplemental\":\"$_ALLOW\"},\"timestamp\":$_TS,\"runId\":\"guard\"}" >> "$_AGENT_LOG" 2>/dev/null || true
# virtio-scsi-single has no inbox WinPE driver; Autounattend RunSynchronous loads vioscsi.inf from the merged supplemental ISO (second CD). Without it, Setup shows no disks (setupact: UnattendSearchSetupSourceDrive / 0x80070002).
_ALLOW_OK=false
case "$_ALLOW" in true|1|yes|TRUE|YES) _ALLOW_OK=true ;; esac
if [ -z "$_SUP" ] && [ "$_ALLOW_OK" = "false" ]; then
  printf '%s\n' "{\"sessionId\":\"d3071e\",\"hypothesisId\":\"H6\",\"location\":\"packer-build-with-render.sh\",\"message\":\"blocked build: supplemental required for virtio-scsi\",\"data\":{\"supplementalEmpty\":true,\"reason\":\"winpe-vioscsi-from-supplemental-iso\"},\"timestamp\":$_TS,\"runId\":\"guard\"}" >> "$_AGENT_LOG" 2>/dev/null || true
  echo "FATAL: PKR_VAR_supplemental_iso_file is empty. WinPE cannot load vioscsi.inf for virtio-scsi-single — disk list will be empty in Setup." >&2
  echo "       Build and upload the merged ISO (packer/scripts/build-supplemental-iso.sh), then set PKR_VAR_supplemental_iso_file=local:iso/<name>.iso in .env / Portainer." >&2
  echo "       To bypass only if you use non-VirtIO storage with inbox drivers: PKR_VAR_allow_build_without_supplemental_iso=true" >&2
  exit 1
fi
_SPRESENT=false
[ -n "$_SUP" ] && _SPRESENT=true
printf '%s\n' "{\"sessionId\":\"d3071e\",\"hypothesisId\":\"H6\",\"location\":\"packer-build-with-render.sh\",\"message\":\"supplemental gate passed\",\"data\":{\"supplementalPresent\":$_SPRESENT,\"allowWithoutOptOut\":$_ALLOW_OK},\"timestamp\":$_TS,\"runId\":\"guard\"}" >> "$_AGENT_LOG" 2>/dev/null || true
# #endregion

exec packer build "$@"
