# WinRM is enabled last so Packer can resolve this VM's IP via the QEMU guest agent
# (proxmox GetVmAgentNetworkInterfaces). VirtIO + qemu-ga must run before WinRM or Packer
# only sees API 500 until the agent responds.
$ErrorActionPreference = "Stop"
$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

Write-Host "Packer bootstrap: VirtIO drivers..."
& (Join-Path $here "install-virtio.ps1")

Write-Host "Packer bootstrap: QEMU guest agent..."
& (Join-Path $here "install-qemu-agent.ps1")

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
