# Renders answer/Autounattend.in.xml -> answer/Autounattend.xml
#   __PKR_WIM_INDEX__     <- PKR_VAR_win11_install_wim_index (default 6). Match ISO: dism /Get-WimInfo
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
$pw = $env:WINRM_PASSWORD
if ([string]::IsNullOrWhiteSpace($pw)) {
    throw 'WINRM_PASSWORD must be set (same value as Packer winrm_password).'
}
$xml = Get-Content -Raw -Path $inPath
$xml = $xml.Replace('__PKR_WIM_INDEX__', $idx)
$xml = $xml.Replace('__INSTALL_FILENAME__', $installFile)
$xml = $xml.Replace('__WINRM_PASSWORD__', $pw)
# UTF-8 without BOM — BOM-prefixed Autounattend.xml breaks Windows Setup XML parsing in PE/OOBE.
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($outPath, $xml, $utf8NoBom)
Write-Host "Rendered $outPath with /IMAGE/INDEX=$idx"

# #region agent log
try {
  $repoRoot = Split-Path -Parent $packerRoot
  $logPath = Join-Path $repoRoot 'debug-d29db6.log'
  $rawOut = Get-Content -Raw -Path $outPath
  $installFrom = $null
  if ($rawOut -match '<InstallFrom>\s*<Path>([^<]+)</Path>') { $installFrom = $Matches[1].Trim() }
  $imgIdx = $null
  if ($rawOut -match '<Key>/IMAGE/INDEX</Key>\s*<Value>([^<]+)</Value>') { $imgIdx = $Matches[1].Trim() }
  $placeholderLeak = [bool]($rawOut -match '__PKR_WIM_INDEX__|__WINRM_PASSWORD__|__INSTALL_FILENAME__')
  $repoReplaceMe = [bool]($rawOut -match '<Value>REPLACE_ME</Value>')
  $bytes = [System.IO.File]::ReadAllBytes($outPath)
  $utf8Bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $kind = if ($installFrom -match 'install\.esd') { 'esd' } elseif ($installFrom -match 'install\.wim') { 'wim' } else { 'other' }
  $payload = [ordered]@{
    sessionId    = 'd29db6'
    hypothesisId = 'H1-H5'
    location     = 'render-autounattend.ps1'
    message      = 'Autounattend rendered (host)'
    data         = @{
      installFromPath = $installFrom
      installFilename = $installFile
      installMediaKind = $kind
      imageIndex      = $imgIdx
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
