# win_console Test Suite

This directory contains comprehensive tests for the win_console library.

## Test Program

`console_test.exe` - A Windows GUI application that can operate in both GUI and CLI modes, demonstrating proper console handling across different terminal environments.

## Running Tests

### Basic Test
```bash
# Git Bash
./target/release/console_test.exe --test

# PowerShell
.\target\release\console_test.exe --test

# CMD
target\release\console_test.exe --test
```

### Compatibility Tests
```bash
./target/release/console_test.exe --compat-test
```

This runs a comprehensive set of compatibility tests covering:

### RustDesk Scenarios Tests
```bash
./target/release/console_test.exe --rustdesk-scenarios
```

This runs actual RustDesk CLI output scenarios covering:

### Print Combinations Tests
```bash
./target/release/console_test.exe --print-test
```

This runs comprehensive print!/println! combination tests with 20 test cases covering:

1. Basic println! without \n
2. println! with leading \n
3. println! with trailing \n
4. println! with middle \n
5. println! with multiple \n
6. println! with \n at various positions
7. Basic print! without \n
8. print! with \n
9. Mixed print! and println!
10. print! with leading \n
11. Empty println!
12. Only \n characters
13. Real-world patterns (like rustdesk --status)
14. Very long lines
15. Multiple consecutive print! then println!
16. print! with \n in middle
17. Alternating print!/println!
18. Triple newline edge cases
19. Starting with \n
20. Ending with multiple \n

**All tests include EXACT line number markers** using uniform `[LN]` format for all lines, making it easy to verify output positioning and alignment.

**Line Numbering System**:
- Every `\n` increments line number by 1
- All lines are marked with `[LN]` format (e.g., `[L1]`, `[L2]`, `[L3]`)
- Empty lines show just `[LN]` with no content
- Content lines show `[LN] content`
- Maximum 2 consecutive empty lines shown to keep output readable
- Example: `println!("[L1]\n[L2] text")` outputs:
  - [L1] (empty line marker)
  - [L2] text (line with content)
  - (L3 is empty from println's \n, would show as [L3])
- This uniform formatting makes it easy to:
  - Verify line numbers are sequential
  - Detect if content is being overwritten or mispositioned
  - Compare output across different terminals (CMD, PowerShell, Git Bash)

### RustDesk Scenarios (Individual Commands)

Individual commands for testing specific scenarios:
- `--rd-version`: Simple version output
- `--rd-build-date`: Build date output
- `--rd-list-options`: Configuration options list with formatted table
- `--rd-status`: Status (service not running) with Chinese text
- `--rd-status-running`: Status when service is running
- `--rd-status-mixed`: Mixed print!/println! pattern from actual code
- `--rd-help`: Full help message

### Compatibility Tests (Detailed)

The compatibility test suite includes 11 comprehensive test cases:

1. **Leading Newline Test**: Demonstrates the issue with `println!("\n...")` and the correct solution
2. **Mixed print!/println! Test**: Shows proper usage patterns
3. **Trailing Newline Test**: Tests handling of trailing `\n`
4. **Empty println! Test**: Verifies blank line handling
5. **Unicode/Chinese Test**: Tests UTF-8/UTF-16 encoding
6. **println! Macro Test**: Demonstrates using the win_console macro

## Test Results by Terminal

| Terminal   | Direct Output | Pipe (`\|`) | Redirect (`>`) | Prompt Push |
|------------|---------------|-------------|----------------|-------------|
| PowerShell | ✅            | ✅          | ❌*            | ✅          |
| Git Bash   | ✅            | ✅          | ✅             | N/A         |
| CMD        | ✅            | ⚠️          | ❌*            | ✅          |

*Note: Redirection doesn't work due to Windows GUI application limitations. Use pipes instead.

## Common Issues and Solutions

### Issue 1: First Line Overwritten by Prompt

**Problem**:
```rust
println!("\n=== Header ===");  // ❌ Leading \n causes issues
```

**Solution**:
```rust
println!("=== Header ===");  // ✅ No leading \n
println!();                   // ✅ Use separate println!() for blank lines
```

### Issue 2: Output Not Visible

**Cause**: Not calling `win_console::init()`

**Solution**:
```rust
fn main() {
    win_console::init();  // Must call first
    println!("Hello!");
}
```

### Issue 3: Using Standard println!

**Problem**: Using `std::println!` instead of `win_console::println!`

**Solution**: Import the macro
```rust
#[macro_use]
extern crate win_console;

fn main() {
    win_console::init();
    println!("This now uses win_console!");  // Automatic
}
```

## Building

```bash
cd libs/win_console/tests
cargo build --release
```

## Testing in PowerShell

```powershell
# Test prompt pushing
.\target\release\console_test.exe --help
Write-Host "Check: Did the prompt appear on a new line?"

# Test piping
.\target\release\console_test.exe --version | Set-Content test.txt
Get-Content test.txt
```

## Test Coverage

### Summary
- **Basic Test** (`--test`): Simple console functionality verification
- **Compatibility Tests** (`--compat-test`): 11 comprehensive test cases
- **RustDesk Scenarios** (`--rustdesk-scenarios`): 7 actual RustDesk CLI patterns
- **Print Combinations** (`--print-test`): 20 comprehensive print!/println! tests with line number markers

The compatibility test suite includes 11 comprehensive test cases:

### Basic Tests (1-6)
1. ✅ **Leading newlines** - Tests `println!("\n...")` issue and correct solution
2. ✅ **Mixed print!/println!** - Various combinations of print! and println!
3. ✅ **Trailing newlines** - Handling of `\n` at end of strings
4. ✅ **Empty println!** - Blank line handling
5. ✅ **Unicode/Chinese** - UTF-8/UTF-16 encoding (Chinese, Japanese)
6. ✅ **println! macro** - Format strings, multiple arguments, debug formatting

### Advanced Tests (7-11)
7. ✅ **First line newline variations** - 5 scenarios:
   - Leading \n (problematic)
   - Separate println! (correct)
   - Multiple leading \n
   - Both leading and trailing \n
   - Newline in the middle

8. ✅ **Complex mixed patterns** - Real-world usage:
   - Status indicators (Loading...)
   - Key-value pairs
   - Table output
   - Progress bars
   - Error messages with details

9. ✅ **Whitespace edge cases**:
   - Empty strings
   - Only spaces
   - Tabs
   - Multiple consecutive newlines
   - Special characters

10. ✅ **Real-world patterns** - Actual RustDesk patterns:
    - Status report (before/after fix)
    - Configuration list
    - Chinese status output

11. ✅ **Stress test** - 20 lines continuous output

## Implementation Notes

- **windows_subsystem = "windows"**: Required for GUI mode, but limits redirection
- **PowerShell prompt pushing**: 20ms default delay, configurable
- **UTF-16 console output**: Automatic for terminal output
- **UTF-8 file output**: Automatic for redirected output
