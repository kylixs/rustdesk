@echo off
REM CMD Test Script for Console Module
REM Tests the console output module in CMD environment

echo ========================================
echo Testing Console Module in CMD
echo ========================================
echo.

echo Test 1: --version
..\target\release\console_test.exe --version
echo.

echo Test 2: --help
..\target\release\console_test.exe --help
echo.

echo Test 3: --test (multi-line output)
..\target\release\console_test.exe --test
echo.

echo Test 4: Output capture with redirection
..\target\release\console_test.exe --version > test-output.txt 2>&1
type test-output.txt
del test-output.txt
echo.

echo ========================================
echo All CMD tests completed!
echo ========================================
pause
