# PowerShell Test Script for Console Module
# Tests the console output module in PowerShell environment

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Testing Console Module in PowerShell" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Test 1: Version
Write-Host "Test 1: --version" -ForegroundColor Yellow
..\target\release\console_test.exe --version
Write-Host ""

# Test 2: Help
Write-Host "Test 2: --help" -ForegroundColor Yellow
..\target\release\console_test.exe --help
Write-Host ""

# Test 3: Multi-line output
Write-Host "Test 3: --test (multi-line output)" -ForegroundColor Yellow
..\target\release\console_test.exe --test
Write-Host ""

# Test 4: Output capture with pipe
Write-Host "Test 4: Output capture with pipe" -ForegroundColor Yellow
$output = ..\target\release\console_test.exe --version 2>&1 | Out-String
Write-Host "Captured output: $output"
Write-Host ""

Write-Host "========================================" -ForegroundColor Green
Write-Host "All PowerShell tests completed!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
