# =============================================================================
# Session 6 - Ansible: VirtualBox port forwarding (run on WINDOWS)
#
# Forwards two ports from Windows into the Ubuntu VM:
#   localhost:2222 -> VM port 22    (VS Code Remote-SSH)
#   localhost:8080 -> VM port 8080  (Jenkins web UI)
#
# Requirements: the VM's Adapter 1 is "NAT" (VirtualBox default).
#
# Usage (PowerShell on Windows, VM can be running or powered off):
#   powershell -ExecutionPolicy Bypass -File .\windows-port-forward.ps1
# =============================================================================

$vbox = Join-Path $env:ProgramFiles "Oracle\VirtualBox\VBoxManage.exe"
if (-not (Test-Path $vbox)) {
    Write-Host "VBoxManage.exe not found at $vbox" -ForegroundColor Red
    Write-Host "Use the VirtualBox GUI instead: Settings > Network > Adapter 1 > Advanced > Port Forwarding"
    exit 1
}

Write-Host "Your VirtualBox VMs:" -ForegroundColor Green
& $vbox list vms
Write-Host ""
$vm = Read-Host "Type the VM name exactly as shown above (without quotes)"

$running = (& $vbox list runningvms) -match [regex]::Escape("`"$vm`"")

$rules = @(
    @{ Name = "ssh";     Host = 2222; Guest = 22   },
    @{ Name = "jenkins"; Host = 8080; Guest = 8080 }
)

foreach ($r in $rules) {
    $spec = "$($r.Name),tcp,127.0.0.1,$($r.Host),,$($r.Guest)"
    if ($running) {
        & $vbox controlvm "$vm" natpf1 delete $r.Name 2>$null | Out-Null
        & $vbox controlvm "$vm" natpf1 $spec
    } else {
        & $vbox modifyvm "$vm" --natpf1 delete $r.Name 2>$null | Out-Null
        & $vbox modifyvm "$vm" --natpf1 $spec
    }
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Forwarded localhost:$($r.Host) -> VM:$($r.Guest)" -ForegroundColor Green
    } else {
        Write-Host "Failed to add rule '$($r.Name)'. Is Adapter 1 set to NAT?" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Test from PowerShell:  ssh -p 2222 <your-vm-username>@127.0.0.1"
