$ErrorActionPreference = "Stop"

$virtioDrive = Get-Volume |
  Where-Object { $_.FileSystemLabel -match "virtio|VirtIO" } |
  Select-Object -First 1

if (-not $virtioDrive) {
  throw "VirtIO ISO not found"
}

$drive = "$($virtioDrive.DriveLetter):"

$drivers = Get-ChildItem -Path $drive -Recurse -Filter "*.inf"
foreach ($driver in $drivers) {
  pnputil.exe /add-driver $driver.FullName /install | Out-Host
}
