#!/bin/bash
# Test script to verify leading newline fix
# This tests that println!("\n...") works correctly

echo "=========================================="
echo "Testing Leading Newline Fix"
echo "=========================================="
echo ""

echo "Test 1: rustdesk --status (has leading \\n in middle sections)"
echo "Expected: All sections should be visible, none overwritten by prompt"
echo ""
./target/release/console_test.exe --rd-status
echo ""

echo "=========================================="
echo "Test 2: Compatibility test with various newline patterns"
echo "=========================================="
./target/release/console_test.exe --compat-test 2>&1 | grep -A 10 "First Line Newline"
echo ""

echo "=========================================="
echo "All tests completed!"
echo "If all content is visible without being overwritten, the fix works!"
echo "=========================================="
