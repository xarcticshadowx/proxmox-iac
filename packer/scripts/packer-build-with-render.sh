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
if [ -n "$_SUP" ]; then _SLEN="$(printf '%s' "$_SUP" | wc -c | tr -d ' ')"; else _SLEN=0; fi
if [ -z "$_SUP" ]; then _SEMPTY=true; else _SEMPTY=false; fi
printf '%s\n' "{\"sessionId\":\"d3071e\",\"hypothesisId\":\"H1\",\"location\":\"packer-build-with-render.sh\",\"message\":\"PKR_VAR supplemental before packer build\",\"data\":{\"supplementalEmpty\":$_SEMPTY,\"supplementalLen\":$_SLEN},\"timestamp\":$_TS,\"runId\":\"pre-fix\"}" >> "$_AGENT_LOG" 2>/dev/null || true
# #endregion

exec packer build "$@"
