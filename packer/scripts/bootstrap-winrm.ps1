Set-ExecutionPolicy Bypass -Scope LocalMachine -Force

Enable-PSRemoting -Force
Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true
Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $true

New-NetFirewallRule `
  -DisplayName "Allow WinRM HTTP" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 5985 `
  -Action Allow

winrm quickconfig -quiet
