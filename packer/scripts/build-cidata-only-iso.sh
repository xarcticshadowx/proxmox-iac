#!/bin/sh
# Small ISO with rendered Autounattend + Packer scripts only (volume label: cidata).
# Use with stock virtio-win.iso on a separate CD — see PKR_VAR_virtio_iso_file + PKR_VAR_cidata_iso_file in win11.pkr.hcl.
# Prereq: render-autounattend. Requires: xorriso OR genisoimage/mkisofs (no 7z).
# Usage: sh scripts/build-cidata-only-iso.sh /path/to/cidata.iso
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_ISO="${1:?usage: $0 <out-cidata.iso>}"

if [ ! -f "$ROOT/answer/Autounattend.xml" ]; then
  echo "FATAL: $ROOT/answer/Autounattend.xml missing — run render-autounattend.sh first." >&2
  exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/answer" "$STAGE/scripts"
cp "$ROOT/answer/Autounattend.xml" "$STAGE/Autounattend.xml"
cp "$ROOT/answer/Autounattend.xml" "$STAGE/answer/Autounattend.xml"
for n in bootstrap-winrm install-virtio install-qemu-agent baseline-windows sysprep; do
  cp "$ROOT/scripts/${n}.ps1" "$STAGE/scripts/"
  case "$n" in bootstrap-winrm) cp "$ROOT/scripts/${n}.ps1" "$STAGE/" ;; esac
done

echo "Building cidata-only ISO (label cidata)..."
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
echo "Wrote $OUT_ISO ($SZ bytes). Upload to Proxmox and set PKR_VAR_cidata_iso_file=local:iso/<name>.iso"
echo "Pair with stock virtio-win.iso as PKR_VAR_virtio_iso_file=local:iso/virtio-win-....iso (leave PKR_VAR_supplemental_iso_file empty)."
