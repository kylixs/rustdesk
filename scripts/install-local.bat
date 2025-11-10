@echo off
REM Quick installer for local RustDesk build
REM This script must be run as Administrator


powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\install-local-rustdesk.ps1" %*

pause
