# Renders answer/Autounattend.in.xml -> answer/Autounattend.xml
#   __PKR_WIM_INDEX__  <- PKR_VAR_win11_install_wim_index (default 6). Match ISO: dism /Get-WimInfo
#   __WINRM_PASSWORD__ <- WINRM_PASSWORD (same as Packer winrm_password / repo .env)
$ErrorActionPreference = 'Stop'
$packerRoot = Split-Path -Parent $PSScriptRoot
$inPath = Join-Path $packerRoot 'answer\Autounattend.in.xml'
$outPath = Join-Path $packerRoot 'answer\Autounattend.xml'
$idx = $env:PKR_VAR_win11_install_wim_index
if ([string]::IsNullOrWhiteSpace($idx)) { $idx = '6' }
$pw = $env:WINRM_PASSWORD
if ([string]::IsNullOrWhiteSpace($pw)) {
    throw 'WINRM_PASSWORD must be set (same value as Packer winrm_password).'
}
$xml = Get-Content -Raw -Path $inPath
$xml = $xml.Replace('__PKR_WIM_INDEX__', $idx)
$xml = $xml.Replace('__WINRM_PASSWORD__', $pw)
Set-Content -Path $outPath -Value $xml -Encoding utf8
Write-Host "Rendered $outPath with /IMAGE/INDEX=$idx"
