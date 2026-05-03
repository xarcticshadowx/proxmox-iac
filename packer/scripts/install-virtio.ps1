$ErrorActionPreference = "Stop"

# Matches standalone virtio-win.iso (label VIRTIO*) or merged supplemental ISO (label cidata — see build-supplemental-iso.sh).
$virtioDrive = Get-Volume |
  Where-Object { $_.FileSystemLabel -match "cidata|virtio|VirtIO" } |
  Select-Object -First 1

if (-not $virtioDrive) {
  throw "VirtIO / supplemental ISO not found (expected volume label cidata or virtio)"
}

$drive = "$($virtioDrive.DriveLetter):"

$drivers = Get-ChildItem -Path $drive -Recurse -Filter "*.inf"
foreach ($driver in $drivers) {
  pnputil.exe /add-driver $driver.FullName /install | Out-Host
}
