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
_VIO="${PKR_VAR_virtio_iso_file:-}"
_CID="${PKR_VAR_cidata_iso_file:-}"
_ALLOW="${PKR_VAR_allow_build_without_supplemental_iso:-}"
if [ -n "$_SUP" ]; then _SLEN="$(printf '%s' "$_SUP" | wc -c | tr -d ' ')"; else _SLEN=0; fi
if [ -z "$_SUP" ]; then _SEMPTY=true; else _SEMPTY=false; fi
printf '%s\n' "{\"sessionId\":\"d3071e\",\"hypothesisId\":\"H1\",\"location\":\"packer-build-with-render.sh\",\"message\":\"ISO vars before packer build\",\"data\":{\"supplementalEmpty\":$_SEMPTY,\"supplementalLen\":$_SLEN,\"virtioSet\":$( [ -n \"$_VIO\" ] && echo true || echo false ),\"cidataSet\":$( [ -n \"$_CID\" ] && echo true || echo false ),\"allowBuildWithoutSupplemental\":\"$_ALLOW\"},\"timestamp\":$_TS,\"runId\":\"guard\"}" >> "$_AGENT_LOG" 2>/dev/null || true
_ALLOW_OK=false
case "$_ALLOW" in true|1|yes|TRUE|YES) _ALLOW_OK=true ;; esac

if [ -n "$_SUP" ] && { [ -n "$_VIO" ] || [ -n "$_CID" ]; }; then
  printf '%s\n' "{\"sessionId\":\"d3071e\",\"hypothesisId\":\"H6\",\"location\":\"packer-build-with-render.sh\",\"message\":\"blocked: merged vs split conflict\",\"data\":{\"reason\":\"supplemental-and-split\"},\"timestamp\":$_TS,\"runId\":\"guard\"}" >> "$_AGENT_LOG" 2>/dev/null || true
  echo "FATAL: Use either PKR_VAR_supplemental_iso_file (merged ISO) OR both PKR_VAR_virtio_iso_file + PKR_VAR_cidata_iso_file (stock virtio + cidata-only), not both." >&2
  exit 1
fi

_SPLIT="false"
if [ -n "$_VIO" ] && [ -n "$_CID" ]; then _SPLIT="true"; fi

if { [ -n "$_VIO" ] && [ -z "$_CID" ]; } || { [ -z "$_VIO" ] && [ -n "$_CID" ]; }; then
  printf '%s\n' "{\"sessionId\":\"d3071e\",\"hypothesisId\":\"H6\",\"location\":\"packer-build-with-render.sh\",\"message\":\"blocked: split mode incomplete\",\"data\":{\"reason\":\"need-both-virtio-and-cidata\"},\"timestamp\":$_TS,\"runId\":\"guard\"}" >> "$_AGENT_LOG" 2>/dev/null || true
  echo "FATAL: Split mode requires BOTH PKR_VAR_virtio_iso_file (stock virtio-win.iso) and PKR_VAR_cidata_iso_file (build scripts/build-cidata-only-iso.sh)." >&2
  exit 1
fi

_has_iso=false
[ -n "$_SUP" ] && _has_iso=true
[ "$_SPLIT" = "true" ] && _has_iso=true

if [ "$_has_iso" = "false" ] && [ "$_ALLOW_OK" = "false" ]; then
  printf '%s\n' "{\"sessionId\":\"d3071e\",\"hypothesisId\":\"H6\",\"location\":\"packer-build-with-render.sh\",\"message\":\"blocked: no driver/unattend ISO\",\"data\":{\"reason\":\"merged-or-split-required\"},\"timestamp\":$_TS,\"runId\":\"guard\"}" >> "$_AGENT_LOG" 2>/dev/null || true
  echo "FATAL: Set PKR_VAR_supplemental_iso_file (merged), OR PKR_VAR_virtio_iso_file + PKR_VAR_cidata_iso_file (split — stock virtio + cidata-only ISO)." >&2
  echo "       WinPE needs virtio-win on a CD for virtio-scsi; unattend/bootstrap need cidata CD or merged ISO." >&2
  echo "       Bypass only with inbox storage drivers: PKR_VAR_allow_build_without_supplemental_iso=true" >&2
  exit 1
fi

_MODE_JSON='"allow-opt-out"'
if [ "$_SPLIT" = "true" ]; then _MODE_JSON='"split"'
elif [ -n "$_SUP" ]; then _MODE_JSON='"merged"'
fi
printf '%s\n' "{\"sessionId\":\"d3071e\",\"hypothesisId\":\"H6\",\"location\":\"packer-build-with-render.sh\",\"message\":\"ISO gate passed\",\"data\":{\"mode\":$_MODE_JSON},\"timestamp\":$_TS,\"runId\":\"guard\"}" >> "$_AGENT_LOG" 2>/dev/null || true
# #endregion

exec packer build "$@"
