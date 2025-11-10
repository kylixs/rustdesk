#!/bin/bash
# Git Bash Test Script for Console Module
# Tests the console output module in Git Bash environment

echo "========================================"
echo "Testing Console Module in Git Bash"
echo "========================================"
echo ""

echo "Test 1: --version"
../target/release/console_test.exe --version
echo ""

echo "Test 2: --help"
../target/release/console_test.exe --help
echo ""

echo "Test 3: --test (multi-line output)"
../target/release/console_test.exe --test
echo ""

echo "Test 4: Output capture with pipe"
output=$(../target/release/console_test.exe --version 2>&1)
echo "Captured output: $output"
echo ""

echo "========================================"
echo "All Git Bash tests completed!"
echo "========================================"
