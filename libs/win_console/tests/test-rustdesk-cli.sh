#!/bin/bash
# Test script for RustDesk CLI scenarios
# Each command simulates the actual RustDesk CLI behavior

echo "=========================================="
echo "RustDesk CLI Scenarios - Individual Tests"
echo "=========================================="
echo ""

echo "1. Testing: rustdesk --version"
echo "   Command: ./target/release/console_test.exe --rd-version"
echo "   Output:"
./target/release/console_test.exe --rd-version
echo ""

echo "2. Testing: rustdesk --build-date"
echo "   Command: ./target/release/console_test.exe --rd-build-date"
echo "   Output:"
./target/release/console_test.exe --rd-build-date
echo ""

echo "3. Testing: rustdesk --list-options"
echo "   Command: ./target/release/console_test.exe --rd-list-options"
echo "   Output:"
./target/release/console_test.exe --rd-list-options
echo ""

echo "4. Testing: rustdesk --status (service not running)"
echo "   Command: ./target/release/console_test.exe --rd-status"
echo "   Output:"
./target/release/console_test.exe --rd-status
echo ""

echo "5. Testing: rustdesk --status (service running)"
echo "   Command: ./target/release/console_test.exe --rd-status-running"
echo "   Output (first 30 lines):"
./target/release/console_test.exe --rd-status-running | head -30
echo ""

echo "6. Testing: rustdesk --help"
echo "   Command: ./target/release/console_test.exe --rd-help"
echo "   Output (first 25 lines):"
./target/release/console_test.exe --rd-help | head -25
echo ""

echo "=========================================="
echo "All RustDesk CLI scenarios tested!"
echo "=========================================="
