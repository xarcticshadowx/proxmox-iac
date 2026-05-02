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
if ($xml -match '__WIM_META_KEY__|__WIM_META_VALUE__|__INSTALL_FILENAME__|__WINRM_PASSWORD__') {
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
  $logPath = Join-Path $repoRoot 'debug-d29db6.log'
  $rawOut = Get-Content -Raw -Path $outPath
  $installFrom = $null
  if ($rawOut -match '<InstallFrom>\s*<Path>([^<]+)</Path>') { $installFrom = $Matches[1].Trim() }
  $imgIdx = $null
  if ($rawOut -match '<Key>/IMAGE/INDEX</Key>\s*<Value>([^<]+)</Value>') { $imgIdx = $Matches[1].Trim() }
  $imgNm = $null
  if ($rawOut -match '<Key>/IMAGE/NAME</Key>\s*<Value>([^<]+)</Value>') { $imgNm = $Matches[1].Trim() }
  $placeholderLeak = [bool]($rawOut -match '__WIM_META_KEY__|__WIM_META_VALUE__|__WINRM_PASSWORD__|__INSTALL_FILENAME__')
  $repoReplaceMe = [bool]($rawOut -match '<Value>REPLACE_ME</Value>')
  $bytes = [System.IO.File]::ReadAllBytes($outPath)
  $utf8Bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $kind = if ($installFrom -match 'install\.esd') { 'esd' } elseif ($installFrom -match 'install\.wim') { 'wim' } else { 'other' }
  $installMetaMode = $(if (-not [string]::IsNullOrWhiteSpace($imgName)) { 'name' } else { 'index' })
  $payload = [ordered]@{
    sessionId    = 'd29db6'
    hypothesisId = 'H1-H6'
    location     = 'render-autounattend.ps1'
    message      = 'Autounattend rendered (host)'
    data         = @{
      installFromPath = $installFrom
      installFilename = $installFile
      installMediaKind = $kind
      imageIndex      = $imgIdx
      imageName       = $imgNm
      installImageMetaMode = $installMetaMode
      placeholderLeak = $placeholderLeak
      repoReplaceMePasswordStillPresent = $repoReplaceMe
      utf8BomPresent    = $utf8Bom
    }
    timestamp    = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  }
  Add-Content -LiteralPath $logPath -Value (($payload | ConvertTo-Json -Compress -Depth 5)) -Encoding utf8
}
catch { }
# #endregion
