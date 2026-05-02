$ErrorActionPreference = "Stop"

$virtioDrive = Get-Volume |
  Where-Object { $_.FileSystemLabel -match "virtio|VirtIO" } |
  Select-Object -First 1

if (-not $virtioDrive) {
  throw "VirtIO ISO not found"
}

$drive = "$($virtioDrive.DriveLetter):"
$agent = Get-ChildItem -Path $drive -Recurse -Filter "qemu-ga-x86_64.msi" | Select-Object -First 1

if (-not $agent) {
  throw "QEMU guest agent installer not found"
}

Start-Process msiexec.exe -ArgumentList "/i `"$($agent.FullName)`" /qn /norestart" -Wait
Set-Service QEMU-GA -StartupType Automatic
Start-Service QEMU-GA
