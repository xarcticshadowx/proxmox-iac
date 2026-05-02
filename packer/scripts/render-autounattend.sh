#!/bin/sh
# Substitutes __PKR_WIM_INDEX__ in answer/Autounattend.in.xml → answer/Autounattend.xml
# Index must match your ISO: dism /Get-WimInfo /WimFile:X:\sources\install.wim  (or install.esd)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IDX="${PKR_VAR_win11_install_wim_index:-6}"
sed "s/__PKR_WIM_INDEX__/$IDX/g" "$ROOT/answer/Autounattend.in.xml" > "$ROOT/answer/Autounattend.xml"
echo "Rendered Autounattend.xml with /IMAGE/INDEX=$IDX"
