# RustDesk Local Installation Script
# This script installs the locally built RustDesk portable version

param(
    [string]$SourceExe = "",
    [switch]$SkipServiceRestart
)

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Please right-click and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "RustDesk Local Installation Script" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""

# Determine source exe path
if ($SourceExe -eq "") {
    # Default to SignOutput directory
    $possiblePaths = @(
        ".\SignOutput\rustdesk-*.exe",
        "..\SignOutput\rustdesk-*.exe",
        "C:\Users\gongdewei\work\rustdesk\SignOutput\rustdesk-*.exe"
    )

    foreach ($pattern in $possiblePaths) {
        $files = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch "sciter" } | Sort-Object LastWriteTime -Descending
        if ($files) {
            $SourceExe = $files[0].FullName
            break
        }
    }

    if ($SourceExe -eq "") {
        Write-Host "ERROR: Could not find RustDesk portable exe in SignOutput directory" -ForegroundColor Red
        Write-Host "Please specify the path using -SourceExe parameter" -ForegroundColor Yellow
        exit 1
    }
}

# Verify source file exists
if (-not (Test-Path $SourceExe)) {
    Write-Host "ERROR: Source file not found: $SourceExe" -ForegroundColor Red
    exit 1
}

$SourceExe = Resolve-Path $SourceExe
Write-Host "[1/6] Source executable: $SourceExe" -ForegroundColor Green

# Get version from filename
$SourceFileName = Split-Path $SourceExe -Leaf
Write-Host "      File: $SourceFileName" -ForegroundColor Gray

# Define target path
$TargetExe = "C:\Program Files\RustDesk\RustDesk.exe"
$TargetDir = Split-Path $TargetExe -Parent

# Create target directory if it doesn't exist
if (-not (Test-Path $TargetDir)) {
    Write-Host "      Creating directory: $TargetDir" -ForegroundColor Gray
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
}

# Step 1: Stop RustDesk service
Write-Host ""
Write-Host "[2/6] Stopping RustDesk service..." -ForegroundColor Green
$service = Get-Service -Name "RustDesk" -ErrorAction SilentlyContinue
if ($service) {
    if ($service.Status -eq "Running") {
        Write-Host "      Service is running, stopping..." -ForegroundColor Gray
        Stop-Service -Name "RustDesk" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        # Verify service stopped
        $service = Get-Service -Name "RustDesk" -ErrorAction SilentlyContinue
        if ($service.Status -eq "Stopped") {
            Write-Host "      ✓ Service stopped successfully" -ForegroundColor Green
        } else {
            Write-Host "      WARNING: Service status: $($service.Status)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "      Service already stopped (Status: $($service.Status))" -ForegroundColor Gray
    }
} else {
    Write-Host "      RustDesk service not found (will be installed)" -ForegroundColor Yellow
}

# Step 2: Kill all RustDesk processes
Write-Host ""
Write-Host "[3/6] Stopping all RustDesk processes..." -ForegroundColor Green
$processes = Get-Process -Name "rustdesk" -ErrorAction SilentlyContinue
if ($processes) {
    Write-Host "      Found $($processes.Count) RustDesk process(es)" -ForegroundColor Gray
    foreach ($proc in $processes) {
        Write-Host "      Killing PID $($proc.Id)..." -ForegroundColor Gray
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2

    # Verify all processes terminated
    $remaining = Get-Process -Name "rustdesk" -ErrorAction SilentlyContinue
    if ($remaining) {
        Write-Host "      WARNING: $($remaining.Count) process(es) still running" -ForegroundColor Yellow
    } else {
        Write-Host "      ✓ All RustDesk processes terminated" -ForegroundColor Green
    }
} else {
    Write-Host "      No RustDesk processes found" -ForegroundColor Gray
}

# Step 3: Copy executable
Write-Host ""
Write-Host "[4/6] Copying executable..." -ForegroundColor Green
Write-Host "      From: $SourceExe" -ForegroundColor Gray
Write-Host "      To:   $TargetExe" -ForegroundColor Gray

try {
    Copy-Item -Path $SourceExe -Destination $TargetExe -Force
    Write-Host "      ✓ File copied successfully" -ForegroundColor Green

    # Verify file
    if (Test-Path $TargetExe) {
        $targetInfo = Get-Item $TargetExe
        Write-Host "      Size: $([math]::Round($targetInfo.Length / 1MB, 2)) MB" -ForegroundColor Gray

        # Get version info
        $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($TargetExe)
        if ($versionInfo.ProductVersion) {
            Write-Host "      Version: $($versionInfo.ProductVersion)" -ForegroundColor Gray
        }
    }
} catch {
    Write-Host "      ERROR: Failed to copy file: $_" -ForegroundColor Red
    exit 1
}

# Step 4: Clean user extraction directory
Write-Host ""
Write-Host "[5/6] Cleaning extraction directories..." -ForegroundColor Green

# User directory
$userExtractDir = Join-Path $env:LOCALAPPDATA "rustdesk"
if (Test-Path $userExtractDir) {
    Write-Host "      Removing user directory: $userExtractDir" -ForegroundColor Gray
    try {
        Remove-Item -Path $userExtractDir -Recurse -Force -ErrorAction Stop
        Write-Host "      ✓ User directory cleaned" -ForegroundColor Green
    } catch {
        Write-Host "      WARNING: Failed to remove user directory: $_" -ForegroundColor Yellow
    }
} else {
    Write-Host "      User directory not found (OK)" -ForegroundColor Gray
}

# Service directory (SYSTEM profile)
$serviceExtractDir = "C:\Windows\system32\config\systemprofile\AppData\Local\rustdesk"
if (Test-Path $serviceExtractDir) {
    Write-Host "      Removing service directory: $serviceExtractDir" -ForegroundColor Gray
    try {
        Remove-Item -Path $serviceExtractDir -Recurse -Force -ErrorAction Stop
        Write-Host "      ✓ Service directory cleaned" -ForegroundColor Green
    } catch {
        Write-Host "      WARNING: Failed to remove service directory: $_" -ForegroundColor Yellow
    }
} else {
    Write-Host "      Service directory not found (OK)" -ForegroundColor Gray
}

# ProgramData extraction directory (new portable extraction location)
$programDataExtractDir = "C:\ProgramData\RustDesk\bin"
if (Test-Path $programDataExtractDir) {
    Write-Host "      Removing ProgramData directory: $programDataExtractDir" -ForegroundColor Gray
    try {
        Remove-Item -Path $programDataExtractDir -Recurse -Force -ErrorAction Stop
        Write-Host "      ✓ ProgramData directory cleaned" -ForegroundColor Green
    } catch {
        Write-Host "      WARNING: Failed to remove ProgramData directory: $_" -ForegroundColor Yellow
    }
} else {
    Write-Host "      ProgramData directory not found (OK)" -ForegroundColor Gray
}

# Step 5: Start service
if (-not $SkipServiceRestart) {
    Write-Host ""
    Write-Host "[6/6] Starting RustDesk service..." -ForegroundColor Green

    $service = Get-Service -Name "RustDesk" -ErrorAction SilentlyContinue
    if ($service) {
        try {
            Start-Service -Name "RustDesk" -ErrorAction Stop
            Start-Sleep -Seconds 2

            # Verify service started
            $service = Get-Service -Name "RustDesk" -ErrorAction SilentlyContinue
            if ($service.Status -eq "Running") {
                Write-Host "      ✓ Service started successfully" -ForegroundColor Green

                # Get service process info
                $servicePID = (Get-WmiObject -Class Win32_Service -Filter "Name='RustDesk'").ProcessId
                if ($servicePID) {
                    Write-Host "      Service PID: $servicePID" -ForegroundColor Gray
                }
            } else {
                Write-Host "      WARNING: Service status: $($service.Status)" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "      ERROR: Failed to start service: $_" -ForegroundColor Red
            Write-Host "      You may need to check the service manually" -ForegroundColor Yellow
        }
    } else {
        Write-Host "      WARNING: RustDesk service not installed" -ForegroundColor Yellow
        Write-Host "      Please install the service first using:" -ForegroundColor Yellow
        Write-Host "      $TargetExe --install-service" -ForegroundColor Cyan
    }
} else {
    Write-Host ""
    Write-Host "[6/6] Skipping service restart (--SkipServiceRestart specified)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "Installation completed!" -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Check service status: sc.exe query RustDesk" -ForegroundColor White
Write-Host "  2. View DebugView output (run as Administrator with 'Capture Global Win32')" -ForegroundColor White
Write-Host "  3. Check logs and config in:" -ForegroundColor White
Write-Host "     - Logs: C:\ProgramData\RustDesk\log" -ForegroundColor Gray
Write-Host "     - Config: C:\ProgramData\RustDesk\config" -ForegroundColor Gray
Write-Host "     - Extracted exe: C:\ProgramData\RustDesk\bin\<version>" -ForegroundColor Gray
Write-Host ""
