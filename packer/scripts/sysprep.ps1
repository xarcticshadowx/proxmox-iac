$ErrorActionPreference = "Stop"

Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

Start-Process `
  -FilePath "$env:SystemRoot\System32\Sysprep\Sysprep.exe" `
  -ArgumentList "/generalize /oobe /shutdown /quiet" `
  -Wait
