#Requires -Version 5.1
<#
.SYNOPSIS
    Cloudflare Tunnel Manager for Windows
.DESCRIPTION
    A powerful interactive PowerShell script to manage Cloudflare Tunnels.
    Windows replica of the Linux cloudflare-tunnel-manager.sh.
.NOTES
    Author: Dan Ong'udi
    Email:  ongudidan@gmail.com
    Run as Administrator for service management features.
#>

# ── Configuration ──────────────────────────────────────────────────────────────
$CLOUDFLARED_DIR = Join-Path $env:USERPROFILE ".cloudflared"

# ── Helpers ────────────────────────────────────────────────────────────────────

function Test-Administrator {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Elevate-ToAdmin {
    if (-not (Test-Administrator)) {
        $scriptPath = $PSCommandPath
        if (-not $scriptPath) { $scriptPath = $MyInvocation.MyCommand.Path }

        if ($scriptPath -and (Test-Path -LiteralPath $scriptPath)) {
            Write-Host "🔒 Administrator privileges required for Cloudflare Tunnel Manager." -ForegroundColor Yellow
            Write-Host "⚡ Triggering Windows UAC prompt to run as Administrator..." -ForegroundColor Cyan
            Start-Sleep -Seconds 1
            try {
                Start-Process powershell.exe -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$scriptPath`"" -ErrorAction Stop
                exit
            }
            catch {
                Write-Host "❌ Elevation prompt was cancelled or failed." -ForegroundColor Red
                Write-Host "   Some options (installer, service management, boot autostart) will fail without Admin." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
            }
        }
    }
}

function Require-Administrator {
    if (-not (Test-Administrator)) {
        Write-Host "❌ This action requires Administrator privileges." -ForegroundColor Red
        Write-Host "   Attempting auto-elevation..." -ForegroundColor Yellow
        Elevate-ToAdmin
        return (Test-Administrator)
    }
    return $true
}

function Test-CloudflaredInstalled {
    $cmd = Get-Command cloudflared -ErrorAction SilentlyContinue
    if (-not $cmd) {
        # Check standard installation paths before giving up
        $commonPaths = @(
            "C:\Program Files\cloudflared",
            "C:\Program Files (x86)\cloudflared"
        )
        foreach ($p in $commonPaths) {
            $exe = Join-Path $p "cloudflared.exe"
            if (Test-Path $exe) {
                if ($env:Path -notlike "*$p*") {
                    $env:Path = "$p;$env:Path"
                }
                $cmd = Get-Command cloudflared -ErrorAction SilentlyContinue
                if ($cmd) { break }
            }
        }
    }
    if (-not $cmd) {
        Write-Host "❌ cloudflared is not installed or not in PATH." -ForegroundColor Red
        Write-Host "   Use option 1 to install it first." -ForegroundColor Yellow
        return $false
    }
    return $true
}

function Invoke-CloudflaredCmd {
    param([string]$Arguments)

    # Ensure cloudflared path is in PATH for cmd.exe subshell
    $exeCmd = Get-Command cloudflared -ErrorAction SilentlyContinue
    if ($exeCmd) {
        $exeDir = Split-Path $exeCmd.Path
        if ($env:Path -notlike "*$exeDir*") {
            $env:Path = "$exeDir;$env:Path"
        }
    }

    # Execute via cmd.exe to cleanly merge stdout and stderr (2>&1) without PowerShell NativeCommandError wrapper
    $raw = cmd.exe /c "cloudflared $Arguments 2>&1"
    if ($raw) {
        return ($raw -join "`n")
    }
    return ""
}

function Remove-CloudflaredServiceInternal {
    # 1. Force kill any running cloudflared processes so SCM doesn't get stuck in StopPending
    Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    # 2. Stop service if present
    $svc = Get-Service -Name "Cloudflared" -ErrorAction SilentlyContinue
    if ($svc) {
        Stop-Service -Name "Cloudflared" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }

    # 3. Uninstall service via cloudflared CLI and force delete with sc.exe
    Invoke-CloudflaredCmd "service uninstall" | Out-Null
    & sc.exe delete "Cloudflared" 2>&1 | Out-Null
    Start-Sleep -Seconds 2

    # 4. Clean up ProgramData config directory
    $programDataDir = Join-Path $env:ProgramData "cloudflared"
    if (Test-Path $programDataDir) {
        Remove-Item $programDataDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Auto-elevate on script launch to guarantee full functionality
Elevate-ToAdmin

# ── Menu ───────────────────────────────────────────────────────────────────────

function Show-Menu {
    Write-Host ""
    $adminBadge = if (Test-Administrator) { " [Admin Mode]" } else { " [User Mode - Run as Admin for Service tasks]" }
    Write-Host "🚀 Cloudflare Tunnel Manager (Windows)$adminBadge" -ForegroundColor Cyan
    Write-Host "1.  Install cloudflared"
    Write-Host "2.  Authenticate with Cloudflare"
    Write-Host "3.  Create new tunnel (auto config)"
    Write-Host "4.  Edit tunnel config (ingress rules)"
    Write-Host "5.  Route subdomains to tunnel"
    Write-Host "6.  Run tunnel manually"
    Write-Host "7.  Enable/Disable auto-start for tunnel"
    Write-Host "8.  Start/Restart/Stop/View Windows service"
    Write-Host "9.  Delete cloudflared service"
    Write-Host "10. Full uninstall and cleanup"
    Write-Host "11. Delete a tunnel"
    Write-Host "0.  Exit"
    Write-Host -NoNewline "Select an option [0-11]: "
}

# ── Select Tunnel ──────────────────────────────────────────────────────────────

function Select-Tunnel {
    if (-not (Test-CloudflaredInstalled)) { return $null }

    $output = Invoke-CloudflaredCmd "tunnel list"
    $lines = $output -split "`r?\n" | Where-Object { $_.Trim() -ne "" }

    $tunnelList = @()
    # UUID pattern for Cloudflare Tunnel ID
    $guidRegex = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

    foreach ($line in $lines) {
        $parts = $line.Trim() -split '\s+'
        if ($parts.Count -ge 2 -and $parts[0] -match $guidRegex) {
            $tunnelList += $parts[1]
        }
    }

    if ($tunnelList.Count -eq 0) {
        Write-Host "❌ No tunnels found. Create one first." -ForegroundColor Red
        return $null
    }

    Write-Host ""
    Write-Host "📜 Available Tunnels:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $tunnelList.Count; $i++) {
        Write-Host "  $($i + 1). $($tunnelList[$i])"
    }

    $num = Read-Host "Select a tunnel by number"
    if ($num -match '^\d+$') {
        $idx = [int]$num - 1
        if ($idx -ge 0 -and $idx -lt $tunnelList.Count) {
            return $tunnelList[$idx]
        }
    }

    Write-Host "❌ Invalid selection." -ForegroundColor Red
    return $null
}

function Get-TunnelId {
    param([string]$TunnelName)

    $output = Invoke-CloudflaredCmd "tunnel list"
    $lines = $output -split "`r?\n" | Where-Object { $_.Trim() -ne "" }

    $guidRegex = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

    foreach ($line in $lines) {
        $parts = $line.Trim() -split '\s+'
        if ($parts.Count -ge 2 -and $parts[0] -match $guidRegex -and $parts[1] -eq $TunnelName) {
            return $parts[0]
        }
    }
    return $null
}

# ── 1. Install cloudflared ────────────────────────────────────────────────────

function Install-Cloudflared {
    if (-not (Require-Administrator)) { return }

    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }

    switch ($arch) {
        "AMD64"  { $fileArch = "amd64" }
        "ARM64"  { $fileArch = "arm64" }
        "x86"    { $fileArch = "386" }
        default  {
            Write-Host "❌ Unsupported architecture: $arch" -ForegroundColor Red
            return
        }
    }

    $msiUrl  = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-$fileArch.msi"
    $msiFile = Join-Path $env:TEMP "cloudflared-windows-$fileArch.msi"

    Write-Host "📥 Downloading cloudflared for $fileArch architecture..." -ForegroundColor Cyan
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $msiUrl -OutFile $msiFile -UseBasicParsing
    }
    catch {
        Write-Host "❌ Download failed: $_" -ForegroundColor Red
        return
    }

    Write-Host "📦 Installing cloudflared..." -ForegroundColor Cyan

    $msiArgs = "/i `"$msiFile`" /quiet /norestart"
    $process = Start-Process msiexec.exe -ArgumentList $msiArgs -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        Write-Host "❌ MSI installation failed with exit code $($process.ExitCode)." -ForegroundColor Red
        return
    }

    # Refresh PATH for current session
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath    = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path    = "$machinePath;$userPath"

    $commonPaths = @("C:\Program Files\cloudflared", "C:\Program Files (x86)\cloudflared")
    foreach ($p in $commonPaths) {
        if ((Test-Path (Join-Path $p "cloudflared.exe")) -and ($env:Path -notlike "*$p*")) {
            $env:Path = "$p;$env:Path"
        }
    }

    # Verify installation
    $cmd = Get-Command cloudflared -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Host "✅ cloudflared installed successfully!" -ForegroundColor Green
        $verOut = Invoke-CloudflaredCmd "--version"
        Write-Host $verOut
    }
    else {
        Write-Host "⚠️ cloudflared installed but not found in PATH." -ForegroundColor Yellow
        Write-Host "   You may need to restart your terminal or add it to PATH manually." -ForegroundColor Yellow
        Write-Host "   Common location: C:\Program Files\cloudflared\" -ForegroundColor Yellow
    }

    # Clean up downloaded MSI
    Remove-Item $msiFile -Force -ErrorAction SilentlyContinue
}

# ── 2. Authenticate ───────────────────────────────────────────────────────────

function Login-Cloudflare {
    if (-not (Test-CloudflaredInstalled)) { return }
    Write-Host "🔐 Launching Cloudflare authentication..." -ForegroundColor Cyan
    & cloudflared tunnel login
}

# ── 3. Create Tunnel ──────────────────────────────────────────────────────────

function New-Tunnel {
    if (-not (Test-CloudflaredInstalled)) { return }

    $tunnelName = Read-Host "Enter a name for the tunnel"
    if ([string]::IsNullOrWhiteSpace($tunnelName)) {
        Write-Host "❌ Tunnel name cannot be empty." -ForegroundColor Red
        return
    }

    Write-Host "⛏️ Creating tunnel '$tunnelName'..." -ForegroundColor Cyan
    $createOutput = Invoke-CloudflaredCmd "tunnel create `"$tunnelName`""
    Write-Host $createOutput

    Write-Host "🔍 Getting Tunnel ID..." -ForegroundColor Cyan
    $tunnelId = $null
    if ($createOutput -match 'with id\s+([0-9a-fA-F-]{36})') {
        $tunnelId = $Matches[1]
    }
    else {
        $tunnelId = Get-TunnelId -TunnelName $tunnelName
    }

    if ([string]::IsNullOrWhiteSpace($tunnelId)) {
        Write-Host "❌ Failed to get Tunnel ID for '$tunnelName'." -ForegroundColor Red
        return
    }

    # Ensure .cloudflared directory exists
    if (-not (Test-Path $CLOUDFLARED_DIR)) {
        New-Item -ItemType Directory -Path $CLOUDFLARED_DIR -Force | Out-Null
    }

    $credentialsFile = (Join-Path $CLOUDFLARED_DIR "$tunnelId.json") -replace '\\', '/'
    $tunnelConfig    = Join-Path $CLOUDFLARED_DIR "$tunnelName.yml"

    Write-Host "🗒️ Creating config at: $tunnelConfig" -ForegroundColor Cyan

    $configContent = @"
tunnel: $tunnelId
credentials-file: $credentialsFile

ingress:
  # Subdomain 1 (e.g., dev server)
  - hostname: dev.fortunedevs.com
    service: http://localhost:80  # Change to your local server port (e.g., port 80)

  # Subdomain 2 (optional, admin dashboard)
  - hostname: admin.fortunedevs.com
    service: http://localhost:8080

  # Catch-all fallback for undefined subdomains
  - service: http_status:404
"@

    Set-Content -Path $tunnelConfig -Value $configContent -Encoding UTF8

    Write-Host "✅ Tunnel and example config created successfully." -ForegroundColor Green
    Write-Host "🔙 Now run option 4 to edit the config, or 5 to add DNS routes." -ForegroundColor Yellow
}

# ── 4. Edit Tunnel Config ─────────────────────────────────────────────────────

function Edit-TunnelConfig {
    if (-not (Test-CloudflaredInstalled)) { return }

    $tunnelName = Select-Tunnel
    if (-not $tunnelName) { return }

    $tunnelId = Get-TunnelId -TunnelName $tunnelName

    $tunnelConfig    = Join-Path $CLOUDFLARED_DIR "$tunnelName.yml"
    $credentialsFile = (Join-Path $CLOUDFLARED_DIR "$tunnelId.json") -replace '\\', '/'

    if (-not (Test-Path $tunnelConfig)) {
        Write-Host "⚠️ Config file for '$tunnelName' not found." -ForegroundColor Yellow
        Write-Host "🛠️ Creating default config at $tunnelConfig" -ForegroundColor Cyan

        # Ensure directory exists
        if (-not (Test-Path $CLOUDFLARED_DIR)) {
            New-Item -ItemType Directory -Path $CLOUDFLARED_DIR -Force | Out-Null
        }

        $configContent = @"
tunnel: $tunnelId
credentials-file: $credentialsFile

ingress:
  # Subdomain 1 (e.g., dev server)
  - hostname: dev.fortunedevs.com
    service: http://localhost:80  # Change to your local server port (e.g., port 80)

  # Subdomain 2 (optional, admin dashboard)
  - hostname: admin.fortunedevs.com
    service: http://localhost:8080

  # Catch-all fallback for undefined subdomains
  - service: http_status:404
"@

        Set-Content -Path $tunnelConfig -Value $configContent -Encoding UTF8
        Write-Host "✅ Default config created." -ForegroundColor Green
    }

    Write-Host "📄 Opening $tunnelConfig" -ForegroundColor Cyan
    Start-Process notepad.exe -ArgumentList $tunnelConfig -Wait
}

# ── 5. Route DNS ──────────────────────────────────────────────────────────────

function Add-DnsRoute {
    if (-not (Test-CloudflaredInstalled)) { return }

    $tunnelName = Select-Tunnel
    if (-not $tunnelName) { return }

    while ($true) {
        $domain = Read-Host "Enter subdomain to route (e.g., dev.example.com), or 'done' to finish"
        if ($domain -eq "done") { break }
        if ([string]::IsNullOrWhiteSpace($domain)) { continue }

        Write-Host "🔍 Checking if $domain is already routed..." -ForegroundColor Cyan
        $output = Invoke-CloudflaredCmd "tunnel route dns `"$tunnelName`" `"$domain`""

        if ($output -match "already configured") {
            Write-Host "⚠️ $domain is already routed to a tunnel." -ForegroundColor Yellow
            Write-Host "ℹ️ If you want to reassign this domain:" -ForegroundColor Cyan
            Write-Host "   🔙 Log in to the Cloudflare Dashboard and delete the existing DNS record for: $domain" -ForegroundColor Cyan
            Write-Host "   🔁 Then come back and try routing it again." -ForegroundColor Cyan
            continue
        }

        Write-Host $output
    }
}

# ── 6. Run Tunnel Manually ────────────────────────────────────────────────────

function Start-TunnelManual {
    if (-not (Test-CloudflaredInstalled)) { return }

    $tunnelName = Select-Tunnel
    if (-not $tunnelName) { return }

    $tunnelConfig = Join-Path $CLOUDFLARED_DIR "$tunnelName.yml"

    if (-not (Test-Path $tunnelConfig)) {
        Write-Host "❌ Config file not found: $tunnelConfig" -ForegroundColor Red
        return
    }

    Write-Host "🚀 Starting tunnel '$tunnelName'..." -ForegroundColor Cyan
    & cloudflared tunnel --config $tunnelConfig run $tunnelName
}

# ── 7. Toggle Auto-Start ──────────────────────────────────────────────────────

function Set-TunnelAutostart {
    if (-not (Test-CloudflaredInstalled)) { return }

    $tunnelName = Select-Tunnel
    if (-not $tunnelName) { return }

    $tunnelConfig = Join-Path $CLOUDFLARED_DIR "$tunnelName.yml"

    if (-not (Test-Path $tunnelConfig)) {
        Write-Host "❌ Config file not found: $tunnelConfig" -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "⚙️ What would you like to do?" -ForegroundColor Yellow
    Write-Host "1. Enable auto-start for '$tunnelName'"
    Write-Host "2. Disable auto-start for '$tunnelName'"
    $action = Read-Host "Select option [1-2]"

    switch ($action) {
        "1" {
            if (-not (Require-Administrator)) { return }

            Write-Host "🧹 Cleaning existing service and processes..." -ForegroundColor Cyan
            Remove-CloudflaredServiceInternal

            # Ensure ProgramData cloudflared directory exists
            $programDataDir = Join-Path $env:ProgramData "cloudflared"
            if (-not (Test-Path $programDataDir)) {
                New-Item -ItemType Directory -Path $programDataDir -Force | Out-Null
            }

            # Get Tunnel ID
            $tunnelId = Get-TunnelId -TunnelName $tunnelName
            if ($tunnelId) {
                $userCredFile = Join-Path $CLOUDFLARED_DIR "$tunnelId.json"
                if (Test-Path $userCredFile) {
                    # Copy credentials file into ProgramData for background system service access on boot
                    Copy-Item -Path $userCredFile -Destination (Join-Path $programDataDir "$tunnelId.json") -Force
                }
            }

            # Copy and prepare config file in ProgramData
            $programDataConfig = Join-Path $programDataDir "config.yml"
            $configContent = Get-Content $tunnelConfig -Raw

            if ($tunnelId) {
                $programDataCredPath = (Join-Path $programDataDir "$tunnelId.json") -replace '\\', '/'
                if ($configContent -match 'credentials-file:') {
                    $configContent = $configContent -replace 'credentials-file:.*', "credentials-file: $programDataCredPath"
                }
            }

            Set-Content -Path $programDataConfig -Value $configContent -Encoding UTF8

            # Locate cloudflared binary executable path
            $cloudflaredExe = "C:\Program Files (x86)\cloudflared\cloudflared.exe"
            if (-not (Test-Path $cloudflaredExe)) {
                $cloudflaredExe = "C:\Program Files\cloudflared\cloudflared.exe"
            }
            $cmdCheck = Get-Command cloudflared -ErrorAction SilentlyContinue
            if ($cmdCheck) { $cloudflaredExe = $cmdCheck.Path }

            Write-Host "⚙️ Installing Windows Service for '$tunnelName'..." -ForegroundColor Cyan
            $installOut = Invoke-CloudflaredCmd "--config `"$programDataConfig`" service install"
            Write-Host $installOut

            # Update Service ImagePath directly in Windows Registry to ensure 'tunnel --config <path> run' is executed
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Cloudflared"
            if (Test-Path $regPath) {
                $targetImagePath = "`"$cloudflaredExe`" tunnel --config `"$programDataConfig`" run"
                Set-ItemProperty -Path $regPath -Name "ImagePath" -Value $targetImagePath -Force -ErrorAction SilentlyContinue
            }

            # Force kill any lingering processes and start service cleanly
            Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1

            Set-Service -Name "Cloudflared" -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service -Name "Cloudflared" -ErrorAction SilentlyContinue

            Start-Sleep -Seconds 3
            $svc = Get-Service -Name "Cloudflared" -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -eq "Running") {
                Write-Host "✅ Tunnel '$tunnelName' is live and will auto-start on boot." -ForegroundColor Green
                Write-Host "📊 Windows Service Status: $($svc.Status)" -ForegroundColor Cyan
            }
            else {
                Write-Host "❌ Service installation failed or stopped. Check logs with option 8 -> d." -ForegroundColor Red
            }
        }

        "2" {
            if (-not (Require-Administrator)) { return }

            Write-Host "🛑 Disabling cloudflared auto-start service..." -ForegroundColor Cyan
            Remove-CloudflaredServiceInternal

            Write-Host "✅ Auto-start has been disabled for '$tunnelName'." -ForegroundColor Green
        }

        default {
            Write-Host "❌ Invalid selection." -ForegroundColor Red
        }
    }
}

# ── 8. Manage Service ─────────────────────────────────────────────────────────

function Manage-Service {
    if (-not (Require-Administrator)) { return }

    Write-Host "a. Start / Restart"
    Write-Host "b. Stop"
    Write-Host "c. Status"
    Write-Host "d. View Logs"
    $action = Read-Host "Choose action [a-d]"

    switch ($action) {
        "a" {
            $svc = Get-Service -Name "Cloudflared" -ErrorAction SilentlyContinue
            if (-not $svc) {
                Write-Host "❌ Cloudflared service is not installed. Use Option 7 to enable auto-start service." -ForegroundColor Red
                return
            }
            if ($svc.Status -eq "Running") {
                Write-Host "🔄 Restarting cloudflared service..." -ForegroundColor Cyan
                Restart-Service -Name "Cloudflared" -Force -ErrorAction SilentlyContinue
            } else {
                Write-Host "🚀 Starting cloudflared service..." -ForegroundColor Cyan
                Start-Service -Name "Cloudflared" -ErrorAction SilentlyContinue
            }
            Start-Sleep -Seconds 1
            $svc.Refresh()
            Write-Host "✅ Service status: $($svc.Status)" -ForegroundColor Green
        }
        "b" {
            $svc = Get-Service -Name "Cloudflared" -ErrorAction SilentlyContinue
            if (-not $svc) {
                Write-Host "❌ Cloudflared service is not installed." -ForegroundColor Red
                return
            }
            Write-Host "🛑 Stopping cloudflared service..." -ForegroundColor Cyan
            Stop-Service -Name "Cloudflared" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            $svc.Refresh()
            Write-Host "✅ Service status: $($svc.Status)" -ForegroundColor Green
        }
        "c" {
            $svc = Get-Service -Name "Cloudflared" -ErrorAction SilentlyContinue
            if ($svc) {
                Write-Host ""
                Write-Host "📊 Service Status:" -ForegroundColor Cyan
                Write-Host "   Name:    $($svc.Name)"
                Write-Host "   Display: $($svc.DisplayName)"
                Write-Host "   Status:  $($svc.Status)"
                Write-Host "   Startup: $($svc.StartType)"
            }
            else {
                Write-Host "❌ Cloudflared service is not installed." -ForegroundColor Red
            }
        }
        "d" {
            Write-Host "📜 Fetching recent cloudflared log entries..." -ForegroundColor Cyan
            Write-Host "   (Press Ctrl+C to stop)" -ForegroundColor Yellow
            Write-Host ""

            # Try Application log first, then System log
            try {
                $logs = Get-WinEvent -FilterHashtable @{
                    LogName      = 'Application'
                    ProviderName = 'cloudflared'
                } -MaxEvents 50 -ErrorAction Stop

                foreach ($entry in ($logs | Sort-Object TimeCreated)) {
                    $time = $entry.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
                    Write-Host "[$time] $($entry.Message)"
                }
            }
            catch {
                Write-Host "⚠️ No cloudflared entries found in Application log." -ForegroundColor Yellow
                Write-Host "   Trying System log..." -ForegroundColor Yellow
                try {
                    $logs = Get-WinEvent -FilterHashtable @{
                        LogName = 'System'
                    } -MaxEvents 100 -ErrorAction Stop |
                        Where-Object { $_.Message -match "cloudflared" }

                    if ($logs) {
                        foreach ($entry in ($logs | Sort-Object TimeCreated)) {
                            $time = $entry.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
                            Write-Host "[$time] $($entry.Message)"
                        }
                    }
                    else {
                        Write-Host "ℹ️ No cloudflared log entries found." -ForegroundColor Cyan
                        Write-Host "   cloudflared may log to its own file at:" -ForegroundColor Cyan
                        Write-Host "   $env:ProgramData\cloudflared\cloudflared.log" -ForegroundColor Cyan
                        $logFile = Join-Path $env:ProgramData "cloudflared\cloudflared.log"
                        if (Test-Path $logFile) {
                            Write-Host ""
                            Write-Host "📄 Last 50 lines from log file:" -ForegroundColor Cyan
                            Get-Content $logFile -Tail 50
                        }
                    }
                }
                catch {
                    Write-Host "ℹ️ Could not retrieve logs. Check manually:" -ForegroundColor Yellow
                    Write-Host "   Event Viewer > Application or:" -ForegroundColor Yellow
                    Write-Host "   $env:ProgramData\cloudflared\cloudflared.log" -ForegroundColor Yellow
                }
            }
        }
        default {
            Write-Host "❌ Invalid option." -ForegroundColor Red
        }
    }
}

# ── 9. Delete Service ─────────────────────────────────────────────────────────

function Remove-CloudflaredService {
    if (-not (Require-Administrator)) { return }

    Write-Host "🧹 Cleaning up cloudflared service..." -ForegroundColor Cyan
    Remove-CloudflaredServiceInternal
    Write-Host "✅ System cloudflared service removed." -ForegroundColor Green
}

# ── 10. Full Uninstall ────────────────────────────────────────────────────────

function Remove-Everything {
    Write-Host "⚠️ This will completely remove cloudflared, all tunnels, configs, credentials, and services from your system." -ForegroundColor Yellow
    Write-Host "❌ This action is irreversible and should only be done if you want a full reset." -ForegroundColor Red

    $confirm = Read-Host "Are you sure you want to proceed? [y/N]"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Host "❌ Full cleanup cancelled." -ForegroundColor Red
        return
    }

    # Remove service first
    if (Test-Administrator) {
        Remove-CloudflaredServiceInternal
    }
    else {
        Write-Host "⚠️ Skipping service removal (not running as Administrator)." -ForegroundColor Yellow
    }

    # Remove credentials, configs, and cert
    if (Test-Path $CLOUDFLARED_DIR) {
        Write-Host "🧹 Removing credentials and configs from $CLOUDFLARED_DIR..." -ForegroundColor Cyan
        Remove-Item -Path (Join-Path $CLOUDFLARED_DIR "*.json") -Force -ErrorAction SilentlyContinue
        Remove-Item -Path (Join-Path $CLOUDFLARED_DIR "*.yml")  -Force -ErrorAction SilentlyContinue
        Remove-Item -Path (Join-Path $CLOUDFLARED_DIR "cert.pem") -Force -ErrorAction SilentlyContinue
    }

    # Remove ProgramData configs
    $programDataDir = Join-Path $env:ProgramData "cloudflared"
    if (Test-Path $programDataDir) {
        Write-Host "🧹 Removing $programDataDir..." -ForegroundColor Cyan
        Remove-Item -Path $programDataDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Uninstall MSI
    Write-Host "🗑️ Uninstalling cloudflared..." -ForegroundColor Cyan
    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $cloudflaredPkg = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match "cloudflared" } |
        Select-Object -First 1

    if ($cloudflaredPkg -and $cloudflaredPkg.UninstallString) {
        $uninstallCmd = $cloudflaredPkg.UninstallString
        if ($uninstallCmd -match "msiexec") {
            # Extract product code and run quiet uninstall
            if ($uninstallCmd -match '\{[A-F0-9\-]+\}') {
                $productCode = $Matches[0]
                Start-Process msiexec.exe -ArgumentList "/x $productCode /quiet /norestart" -Wait
            }
            else {
                Start-Process cmd.exe -ArgumentList "/c $uninstallCmd /quiet" -Wait
            }
        }
    }
    else {
        Write-Host "⚠️ Could not find cloudflared in installed programs." -ForegroundColor Yellow
        Write-Host "   You may need to manually remove it from Add/Remove Programs." -ForegroundColor Yellow
    }

    # Refresh PATH
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath    = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path    = "$machinePath;$userPath"

    Write-Host "✅ Everything has been removed." -ForegroundColor Green
}

# ── 11. Delete a Tunnel ───────────────────────────────────────────────────────

function Remove-Tunnel {
    if (-not (Test-CloudflaredInstalled)) { return }

    $tunnelName = Select-Tunnel
    if (-not $tunnelName) { return }

    $tunnelId = Get-TunnelId -TunnelName $tunnelName
    if ([string]::IsNullOrWhiteSpace($tunnelId)) {
        Write-Host "❌ Unable to find tunnel ID for '$tunnelName'." -ForegroundColor Red
        return
    }

    Write-Host "⚠️ Are you sure you want to delete tunnel '$tunnelName' (ID: $tunnelId)? This cannot be undone." -ForegroundColor Yellow
    $confirm = Read-Host "Type 'yes' to confirm"
    if ($confirm -ne "yes") {
        Write-Host "❌ Cancelled." -ForegroundColor Red
        return
    }

    Write-Host "🛑 Stopping any running cloudflared processes..." -ForegroundColor Cyan
    # Stop the Windows service if running
    $svc = Get-Service -Name "Cloudflared" -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Stop-Service -Name "Cloudflared" -Force -ErrorAction SilentlyContinue
    }
    # Kill any matching cloudflared processes
    Get-CimInstance Win32_Process -Filter "Name='cloudflared.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -match [regex]::Escape($tunnelName) } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }

    Write-Host "🧹 Cleaning up tunnel connections..." -ForegroundColor Cyan
    Invoke-CloudflaredCmd "tunnel cleanup `"$tunnelName`"" | Out-Null

    Write-Host "🗑️ Attempting to delete the tunnel..." -ForegroundColor Cyan
    $delOut = Invoke-CloudflaredCmd "tunnel delete `"$tunnelName`""
    Write-Host $delOut
    if ($LASTEXITCODE -ne 0 -and $delOut -match "error|failed") {
        Write-Host "❌ Failed to delete tunnel. Please ensure no active cloudflared processes are using it." -ForegroundColor Red
        Write-Host "   Run this to check: Get-Process cloudflared" -ForegroundColor Yellow
        return
    }

    $credFile   = Join-Path $CLOUDFLARED_DIR "$tunnelId.json"
    $configFile = Join-Path $CLOUDFLARED_DIR "$tunnelName.yml"
    Remove-Item $credFile   -Force -ErrorAction SilentlyContinue
    Remove-Item $configFile -Force -ErrorAction SilentlyContinue

    Write-Host "✅ Tunnel '$tunnelName' and related files removed." -ForegroundColor Green
}

# ── Main Loop ──────────────────────────────────────────────────────────────────

while ($true) {
    Show-Menu
    $choice = Read-Host

    switch ($choice) {
        "1"  { Install-Cloudflared }
        "2"  { Login-Cloudflare }
        "3"  { New-Tunnel }
        "4"  { Edit-TunnelConfig }
        "5"  { Add-DnsRoute }
        "6"  { Start-TunnelManual }
        "7"  { Set-TunnelAutostart }
        "8"  { Manage-Service }
        "9"  { Remove-CloudflaredService }
        "10" { Remove-Everything }
        "11" { Remove-Tunnel }
        "0"  { Write-Host "👋 Exiting..." -ForegroundColor Cyan; exit }
        default { Write-Host "❌ Invalid choice." -ForegroundColor Red }
    }
}
