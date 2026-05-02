$ErrorActionPreference = "Stop"

powercfg /hibernate off
powercfg /change standby-timeout-ac 0
powercfg /change monitor-timeout-ac 15
powercfg /setactive SCHEME_MIN

Set-ItemProperty `
  -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
  -Name "fDenyTSConnections" `
  -Value 0

Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

Set-ItemProperty `
  -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" `
  -Name "UserAuthentication" `
  -Value 1

New-ItemProperty `
  -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations" `
  -Name "DWMFRAMEINTERVAL" `
  -PropertyType DWord `
  -Value 15 `
  -Force
