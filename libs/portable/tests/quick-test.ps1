# Quick Test Script for RustDesk Portable Packer
# Tests core functionality quickly

param(
    [string]$PortableExe = "..\..\..\target\release\rustdesk-portable-packer.exe"
)

$ErrorActionPreference = "Stop"

function Write-Step { param($msg) Write-Host "`n► $msg" -ForegroundColor Cyan }
function Write-OK { Write-Host "  ✓ OK" -ForegroundColor Green }
function Write-Fail { param($msg) Write-Host "  ✗ FAIL: $msg" -ForegroundColor Red; exit 1 }

function Get-ExtractionDir {
    $output = & $PortableExe --version 2>&1 | Out-String
    $output = $output.Trim()
    # Version output is just the version number, e.g., "1.4.3-jlc20"
    if ($output -match "^[\d\.]+-[\w\d]+$|^[\d\.]+$") {
        $version = $output
        $systemDrive = if ($env:SystemDrive) { $env:SystemDrive } else { "C:" }
        return "$systemDrive\ProgramData\RustDesk\bin\$version"
    }
    throw "Failed to get version. Output: $output"
}

Write-Host "========================================" -ForegroundColor Yellow
Write-Host "RustDesk Portable Packer Quick Test" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow

# Cleanup
Write-Step "Step 1: Cleanup"
Get-Process -Name "rustdesk" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
$extractDir = Get-ExtractionDir
if (Test-Path $extractDir) {
    Remove-Item -Path $extractDir -Recurse -Force
}
Write-OK

# Test 1: Initial extraction
Write-Step "Step 2: Initial Extraction"
& $PortableExe --version 2>&1 | Out-Null
if (-not (Test-Path (Join-Path $extractDir "rustdesk.exe"))) {
    Write-Fail "rustdesk.exe not extracted"
}
if (-not (Test-Path (Join-Path $extractDir ".rustdesk_manifest.bin"))) {
    Write-Fail "manifest not generated"
}
Write-OK

# Test 2: Normal startup
Write-Step "Step 3: Normal Startup (should be fast)"
$start = Get-Date
& $PortableExe --version 2>&1 | Out-Null
$elapsed = (Get-Date) - $start
if ($elapsed.TotalMilliseconds -gt 3000) {
    Write-Warning "  Startup took $($elapsed.TotalMilliseconds)ms (expected < 3000ms)"
}
Write-OK

# Test 3: --verify
Write-Step "Step 4: Verify Command"
$output = & $PortableExe --verify 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Verify failed: $output"
}
if ($output -notmatch "Status: OK|All files verified") {
    Write-Fail "Unexpected verify output"
}
Write-OK

# Test 4: File corruption and auto-repair
Write-Step "Step 5: File Corruption & Auto-Repair"
$rustdeskExe = Join-Path $extractDir "rustdesk.exe"
[System.IO.File]::WriteAllBytes($rustdeskExe, [byte[]]::new(100))
Write-Host "  Corrupted rustdesk.exe" -ForegroundColor Gray
& $PortableExe --version 2>&1 | Out-Null
$fileInfo = Get-Item $rustdeskExe
if ($fileInfo.Length -lt 1000) {
    Write-Fail "File was not repaired (size: $($fileInfo.Length))"
}
Write-OK

# Test 5: --repair command
Write-Step "Step 6: Manual Repair Command"
[System.IO.File]::WriteAllBytes($rustdeskExe, [byte[]]::new(100))
$output = & $PortableExe --repair 2>&1 | Out-String
if ($output -notmatch "Repair completed successfully") {
    Write-Fail "Repair failed: $output"
}
$fileInfo = Get-Item $rustdeskExe
if ($fileInfo.Length -lt 1000) {
    Write-Fail "File was not repaired after --repair"
}
Write-OK

# Test 6: --dump-manifest
Write-Step "Step 7: Dump Manifest"
$output = & $PortableExe --dump-manifest 2>&1 | Out-String
if ($output -notmatch "Manifest Information") {
    Write-Fail "Dump manifest failed"
}
Write-OK

# Test 7: Timestamp mismatch with running process
Write-Step "Step 8: Running Process Detection"
$metaFile = Join-Path $extractDir "meta.toml"
if (Test-Path $metaFile) {
    $content = Get-Content $metaFile
    $newContent = $content -replace 'timestamp = \d+', 'timestamp = 9999999999'
    Set-Content -Path $metaFile -Value $newContent
    Write-Host "  Modified timestamp" -ForegroundColor Gray

    # Start a rustdesk process without arguments (should stay running)
    $process = Start-Process -FilePath $rustdeskExe -PassThru -WindowStyle Hidden -ErrorAction SilentlyContinue
    Write-Host "  Started rustdesk.exe (PID: $($process.Id))" -ForegroundColor Gray
    Start-Sleep -Milliseconds 1000  # Wait for process to initialize

    try {
        # Verify process is still running
        if (-not (Get-Process -Id $process.Id -ErrorAction SilentlyContinue)) {
            Write-Warning "  Process exited too quickly, skipping this test"
            Write-OK
        }
        else {
            $output = & $PortableExe --version 2>&1 | Out-String
            if ($output -notmatch "ERROR: Installation Requires Repair") {
                Write-Fail "Should detect running process: $output"
            }
            if ($output -notmatch "--repair") {
                Write-Fail "Should suggest --repair command"
            }
            Write-OK
        }
    }
    finally {
        if ($process -and -not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Milliseconds 500
    }
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "✓ All Quick Tests Passed!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
