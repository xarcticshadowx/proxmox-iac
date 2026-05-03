# Renders answer/Autounattend.in.xml -> answer/Autounattend.xml
#   __WIM_META_*          <- PKR_VAR_win11_install_wim_index (default 6) OR PKR_VAR_win11_install_image_name (Name from dism /Get-WimInfo; overrides index)
#   __INSTALL_FILENAME__  <- PKR_VAR_win11_install_filename (default install.wim for full VL/CCCOMA ISOs; install.esd for many MCT retail ISOs)
#   __WINRM_PASSWORD__    <- WINRM_PASSWORD (same as Packer winrm_password / repo .env)
$ErrorActionPreference = 'Stop'
$packerRoot = Split-Path -Parent $PSScriptRoot
$inPath = Join-Path $packerRoot 'answer\Autounattend.in.xml'
$outPath = Join-Path $packerRoot 'answer\Autounattend.xml'
$idx = $env:PKR_VAR_win11_install_wim_index
if ([string]::IsNullOrWhiteSpace($idx)) { $idx = '6' }
$installFile = $env:PKR_VAR_win11_install_filename
if ([string]::IsNullOrWhiteSpace($installFile)) { $installFile = 'install.wim' }
$imgName = $env:PKR_VAR_win11_install_image_name
if (-not [string]::IsNullOrWhiteSpace($imgName)) {
    Write-Warning 'PKR_VAR_win11_install_image_name is set: must match dism /Get-WimInfo Name exactly. A typo causes Setup to fail. If index 6 is already correct for your ISO, remove PKR_VAR_win11_install_image_name and use PKR_VAR_win11_install_wim_index only.'
    $metaKey = '/IMAGE/NAME'
    $metaVal = [System.Security.SecurityElement]::Escape($imgName.Trim())
} else {
    $metaKey = '/IMAGE/INDEX'
    $metaVal = $idx
}
$pw = $env:WINRM_PASSWORD
if ([string]::IsNullOrWhiteSpace($pw)) {
    throw 'WINRM_PASSWORD must be set (same value as Packer winrm_password).'
}
$xml = Get-Content -Raw -Path $inPath
$xml = $xml.Replace('__WIM_META_KEY__', $metaKey)
$xml = $xml.Replace('__WIM_META_VALUE__', $metaVal)
$xml = $xml.Replace('__INSTALL_FILENAME__', $installFile)
$xml = $xml.Replace('__WINRM_PASSWORD__', $pw)
$rel = $env:PKR_VAR_virtio_vioscsi_rel_path
if ([string]::IsNullOrWhiteSpace($rel)) { $rel = 'vioscsi/w11/amd64' }
$rel = $rel.Trim().Replace('\', '/')
$xml = $xml.Replace('__VIRTIO_PATH_D__', "D:/$rel")
$xml = $xml.Replace('__VIRTIO_PATH_E__', "E:/$rel")
$xml = $xml.Replace('__VIRTIO_PATH_F__', "F:/$rel")
if ($xml -match '__WIM_META_KEY__|__WIM_META_VALUE__|__INSTALL_FILENAME__|__WINRM_PASSWORD__|__VIRTIO_PATH_') {
    throw 'Autounattend.in.xml still contains unresolved placeholders after substitution.'
}
# UTF-8 without BOM — BOM-prefixed Autounattend.xml breaks Windows Setup XML parsing in PE/OOBE.
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($outPath, $xml, $utf8NoBom)
if (-not [string]::IsNullOrWhiteSpace($imgName)) {
    Write-Host "Rendered $outPath with /IMAGE/NAME=$($imgName.Trim())"
} else {
    Write-Host "Rendered $outPath with /IMAGE/INDEX=$idx"
}

# #region agent log
try {
  $repoRoot = Split-Path -Parent $packerRoot
  $logPath = Join-Path $repoRoot 'debug-932ce5.log'
  $rawOut = Get-Content -Raw -Path $outPath
  $installFrom = $null
  $metaKey = $null
  $metaVal = $null
  if ($rawOut -match '(?s)<InstallFrom>(.*?)</InstallFrom>') {
    $ib = $Matches[1]
    if ($ib -match '<Path>([^<]+)</Path>') { $installFrom = $Matches[1].Trim() }
    if ($ib -match '<Key>([^<]+)</Key>') { $metaKey = $Matches[1].Trim() }
    if ($ib -match '<Value>([^<]+)</Value>') { $metaVal = $Matches[1].Trim() }
  }
  $placeholderLeak = [bool]($rawOut -match '__WIM_META_KEY__|__WIM_META_VALUE__|__WINRM_PASSWORD__|__INSTALL_FILENAME__')
  $repoReplaceMe = [bool]($rawOut -match '<Value>REPLACE_ME</Value>')
  $bytes = [System.IO.File]::ReadAllBytes($outPath)
  $utf8Bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $kind = if ($installFrom -match 'install\.esd') { 'esd' } elseif ($installFrom -match 'install\.wim') { 'wim' } else { 'other' }
  $installMetaMode = $(if (-not [string]::IsNullOrWhiteSpace($imgName)) { 'name' } else { 'index' })
  $virtio = [bool]($rawOut -match 'vioscsi\.inf')
  $cloudOff = [bool]($rawOut -match 'DisableCloudOptimizedContent')
  $ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $nameSet = -not [string]::IsNullOrWhiteSpace($imgName)
  $h1 = @{ sessionId = '932ce5'; hypothesisId = 'H1'; location = 'render-autounattend.ps1'; message = 'InstallFrom MetaData (image selection)'; data = @{ metaKey = $metaKey; metaValue = $metaVal; metaMode = $installMetaMode }; timestamp = $ts }
  $h2 = @{ sessionId = '932ce5'; hypothesisId = 'H2'; location = 'render-autounattend.ps1'; message = 'InstallFrom Path vs env filename'; data = @{ installFromPath = $installFrom; pkrInstallFilename = $installFile; pathMediaKind = $kind }; timestamp = $ts }
  $h3 = @{ sessionId = '932ce5'; hypothesisId = 'H3'; location = 'render-autounattend.ps1'; message = 'VirtIO RunSynchronous references vioscsi.inf'; data = @{ vioscsiInfReferenced = $virtio }; timestamp = $ts }
  $h4 = @{ sessionId = '932ce5'; hypothesisId = 'H4'; location = 'render-autounattend.ps1'; message = 'Cloud-update mitigation + placeholder/BOM'; data = @{ disableCloudOptimizedContentLinePresent = $cloudOff; placeholderLeak = $placeholderLeak; utf8BomPresent = $utf8Bom; replaceMeStillPresent = $repoReplaceMe }; timestamp = $ts }
  $h5 = @{ sessionId = '932ce5'; hypothesisId = 'H5'; location = 'render-autounattend.ps1'; message = 'PKR_VAR defaults used at render'; data = @{ pkrWin11InstallWimIndex = $idx; pkrWin11InstallImageNameSet = $nameSet }; timestamp = $ts }
  foreach ($p in @($h1, $h2, $h3, $h4, $h5)) {
    Add-Content -LiteralPath $logPath -Value (($p | ConvertTo-Json -Compress -Depth 6)) -Encoding utf8
  }
}
catch { }
# #endregion
