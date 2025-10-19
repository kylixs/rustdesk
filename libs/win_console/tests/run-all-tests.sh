#!/bin/bash
# Comprehensive test runner for win_console test suite
# This script runs all available test suites and shows the results

echo "╔════════════════════════════════════════════════════╗"
echo "║  win_console Comprehensive Test Suite             ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

# Build first
echo "Building test suite..."
cargo build --release
if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi
echo "✅ Build successful"
echo ""

# Test 1: Basic functionality test
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Running Basic Test"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
./target/release/console_test.exe --test
echo ""

# Test 2: Compatibility tests
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2. Running Compatibility Tests (11 test cases)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
./target/release/console_test.exe --compat-test
echo ""

# Test 3: RustDesk scenarios
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3. Running RustDesk Scenario Tests (7 scenarios)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
./target/release/console_test.exe --rustdesk-scenarios
echo ""

# Test 4: Print combinations
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4. Running Print Combinations Tests (20 test cases)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
./target/release/console_test.exe --print-test
echo ""

# Summary
echo "╔════════════════════════════════════════════════════╗"
echo "║  All Test Suites Completed!                       ║"
echo "║                                                    ║"
echo "║  Total: 39 test cases                             ║"
echo "║  - Basic: 1 test                                   ║"
echo "║  - Compatibility: 11 tests                         ║"
echo "║  - RustDesk Scenarios: 7 tests                     ║"
echo "║  - Print Combinations: 20 tests                    ║"
echo "╚════════════════════════════════════════════════════╝"
