#!/bin/sh
# Merge virtio-win.iso contents with rendered Autounattend + scripts into ONE ISO (volume label: cidata).
# Attach this single ISO as the only "extra" CD in win11.pkr.hcl (see PKR_VAR_supplemental_iso_file).
# Prereq: run render-autounattend first. Requires: 7z (p7zip), xorriso OR genisoimage/mkisofs.
# Usage: sh scripts/build-supplemental-iso.sh /path/to/virtio-win.iso /path/to/supplemental.iso
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$ROOT/.." && pwd)"
VIRTIO_ISO="${1:?usage: $0 <virtio-win.iso> <out.iso>}"
OUT_ISO="${2:?usage: $0 <virtio-win.iso> <out.iso>}"

if [ ! -f "$ROOT/answer/Autounattend.xml" ]; then
  echo "FATAL: $ROOT/answer/Autounattend.xml missing — run render-autounattend.sh first." >&2
  exit 1
fi
if ! command -v 7z >/dev/null 2>&1 && ! command -v 7zz >/dev/null 2>&1; then
  echo "FATAL: need 7z or 7zz in PATH (p7zip)." >&2
  exit 1
fi
SZ7=7z
command -v 7z >/dev/null 2>&1 || SZ7=7zz

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "Extracting virtio ISO..."
"$SZ7" x "$VIRTIO_ISO" "-o$STAGE" -y

# Packer layout + Setup search paths (root Autounattend.xml; FirstLogon uses root bootstrap-winrm.ps1)
mkdir -p "$STAGE/answer" "$STAGE/scripts"
cp "$ROOT/answer/Autounattend.xml" "$STAGE/Autounattend.xml"
cp "$ROOT/answer/Autounattend.xml" "$STAGE/answer/Autounattend.xml"
for n in bootstrap-winrm install-virtio install-qemu-agent baseline-windows sysprep; do
  cp "$ROOT/scripts/${n}.ps1" "$STAGE/scripts/"
  case "$n" in bootstrap-winrm) cp "$ROOT/scripts/${n}.ps1" "$STAGE/" ;; esac
done

echo "Building ISO (label cidata)..."
if command -v xorriso >/dev/null 2>&1; then
  xorriso -as mkisofs -iso-level 3 -full-iso9660-filenames \
    -joliet -joliet-long -rational-rock \
    -volid cidata -o "$OUT_ISO" "$STAGE"
elif command -v genisoimage >/dev/null 2>&1; then
  genisoimage -iso-level 3 -J -l -r -V cidata -o "$OUT_ISO" "$STAGE"
elif command -v mkisofs >/dev/null 2>&1; then
  mkisofs -iso-level 3 -J -l -r -V cidata -o "$OUT_ISO" "$STAGE"
else
  echo "FATAL: need xorriso, genisoimage, or mkisofs in PATH." >&2
  exit 1
fi

SZ="$(wc -c < "$OUT_ISO" | tr -d ' ')"
# #region agent log
LOG="$REPO/debug-932ce5.log"
TS_MS=$(( $(date +%s) * 1000 ))
printf '{"sessionId":"932ce5","hypothesisId":"H6","location":"build-supplemental-iso.sh","message":"Supplemental ISO built (single optical for virtio+cidata)","data":{"outputIsoBytes":%s,"virtioSourcePresent":1},"timestamp":%s}\n' "$SZ" "$TS_MS" >>"$LOG" || true
# #endregion
echo "Wrote $OUT_ISO ($SZ bytes). Upload to Proxmox ISO storage and set PKR_VAR_supplemental_iso_file=local:iso/<name>.iso"
