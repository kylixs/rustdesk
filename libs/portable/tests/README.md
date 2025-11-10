# RustDesk Portable Packer Tests

This directory contains test scripts and documentation for the RustDesk Portable Packer.

## Quick Start

### Run Quick Test (Recommended)
```powershell
cd libs\portable\tests
.\quick-test.ps1
```

### Run Comprehensive Test Suite
```powershell
cd libs\portable\tests
.\test-portable.ps1
```

## Files

| File | Description |
|------|-------------|
| `quick-test.ps1` | Fast 8-step test suite (~30 seconds) |
| `test-portable.ps1` | Comprehensive 14-test suite covering all scenarios |
| `TESTING.md` | Quick start guide with examples |
| `TEST_PLAN.md` | Detailed test scenarios and design documentation |
| `TEST_RESULTS.md` | Latest test results and performance metrics |

## Requirements

- Windows PowerShell 5.1 or later
- Compiled portable packer executable at `../target/release/rustdesk-portable-packer.exe`
- Administrator privileges (for writing to C:\ProgramData)

## Documentation

- **[TESTING.md](TESTING.md)** - Start here for running tests with examples
- **[TEST_PLAN.md](TEST_PLAN.md)** - Understand test coverage and scenarios
- **[TEST_RESULTS.md](TEST_RESULTS.md)** - View latest test results

## Test Coverage

✅ Initial extraction and setup
✅ Fast startup verification
✅ Timestamp mismatch handling
✅ Manifest consistency checks
✅ File corruption auto-repair
✅ Process detection and safe failure
✅ Manual repair command
✅ Verification and diagnostic commands
✅ Performance optimizations

For more details, see [TEST_PLAN.md](TEST_PLAN.md).
