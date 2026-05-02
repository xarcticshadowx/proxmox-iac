# Substitutes __PKR_WIM_INDEX__ in answer/Autounattend.in.xml -> answer/Autounattend.xml
# Set PKR_VAR_win11_install_wim_index. Match ISO: dism /Get-WimInfo on sources\install.wim or install.esd
$ErrorActionPreference = 'Stop'
$packerRoot = Split-Path -Parent $PSScriptRoot
$inPath = Join-Path $packerRoot 'answer\Autounattend.in.xml'
$outPath = Join-Path $packerRoot 'answer\Autounattend.xml'
$idx = $env:PKR_VAR_win11_install_wim_index
if ([string]::IsNullOrWhiteSpace($idx)) { $idx = '6' }
(Get-Content -Raw -Path $inPath) -replace '__PKR_WIM_INDEX__', $idx | Set-Content -Path $outPath -Encoding utf8
Write-Host "Rendered $outPath with /IMAGE/INDEX=$idx"
