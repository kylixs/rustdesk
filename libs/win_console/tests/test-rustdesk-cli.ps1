# PowerShell test script for RustDesk CLI scenarios
# Each command simulates the actual RustDesk CLI behavior

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "RustDesk CLI Scenarios - Individual Tests" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "1. Testing: rustdesk --version" -ForegroundColor Yellow
Write-Host "   Command: .\target\release\console_test.exe --rd-version"
Write-Host "   Output:"
.\target\release\console_test.exe --rd-version
Write-Host ""

Write-Host "2. Testing: rustdesk --build-date" -ForegroundColor Yellow
Write-Host "   Command: .\target\release\console_test.exe --rd-build-date"
Write-Host "   Output:"
.\target\release\console_test.exe --rd-build-date
Write-Host ""

Write-Host "3. Testing: rustdesk --list-options" -ForegroundColor Yellow
Write-Host "   Command: .\target\release\console_test.exe --rd-list-options"
Write-Host "   Output:"
.\target\release\console_test.exe --rd-list-options
Write-Host ""

Write-Host "4. Testing: rustdesk --status (service not running)" -ForegroundColor Yellow
Write-Host "   Command: .\target\release\console_test.exe --rd-status"
Write-Host "   Output:"
.\target\release\console_test.exe --rd-status
Write-Host ""

Write-Host "5. Testing: rustdesk --status (service running)" -ForegroundColor Yellow
Write-Host "   Command: .\target\release\console_test.exe --rd-status-running"
Write-Host "   Output (first 30 lines):"
.\target\release\console_test.exe --rd-status-running | Select-Object -First 30
Write-Host ""

Write-Host "6. Testing: rustdesk --help" -ForegroundColor Yellow
Write-Host "   Command: .\target\release\console_test.exe --rd-help"
Write-Host "   Output (first 25 lines):"
.\target\release\console_test.exe --rd-help | Select-Object -First 25
Write-Host ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "All RustDesk CLI scenarios tested!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
