# win_console

A standalone library for handling console output in Windows GUI applications that need CLI support across different terminals (PowerShell, CMD, Git Bash, etc.).

## Features

- ✅ **Automatic terminal detection**: PowerShell, CMD, Git Bash
- ✅ **Automatic prompt fixes**: Prompt pushing for PowerShell, Enter key for CMD
- ✅ **Auto cleanup**: Exit handler automatically registered
- ✅ **Pipe support**: Works with `|` pipeline operators
- ✅ **Zero config**: Just call `init()` and use

## Usage

```rust
use win_console;

fn main() {
    // Initialize (auto-registers exit handler)
    win_console::init();

    // Use like normal println
    win_console::println("Hello, World!");
    win_console::println("Line 2");

    // Cleanup is automatic - no need to call cleanup()
}
```

## How it Works

### Terminal Detection

Detects parent process to determine terminal type:
- `powershell.exe` → PowerShell mode
- `cmd.exe` → CMD mode
- `bash.exe`/`sh.exe` → Git Bash mode

### PowerShell Prompt Pushing

For PowerShell interactive sessions:
1. Get current cursor position
2. Send Enter key (pushes prompt down)
3. Wait 10ms
4. Move cursor back to original position
5. Clear the line
6. Output content

### CMD Enter Key

For CMD sessions, sends Enter key on exit to trigger new prompt.

### Git Bash

No special handling needed - works automatically.

## Integration

Add to your `Cargo.toml`:

```toml
[dependencies]
win_console = { path = "../libs/win_console" }
```

Then in your code:

```rust
use win_console;

fn main() {
    if is_cli_mode {
        win_console::init();
        win_console::println("CLI output");
    }
}
```

## API

### `init() -> bool`

Initialize console handling. Returns `true` if successfully attached to parent console.

### `println(text: &str)`

Print a line with automatic terminal handling.

### `print(text: &str)`

Print without newline with automatic terminal handling.

## Known Limitations

### File Redirection (>)

Due to Windows limitations, programs compiled with `windows_subsystem = "windows"` cannot use shell file redirection (`>`) directly:

```powershell
# ❌ Direct redirection does not work
rustdesk.exe --help > output.txt

# ✅ PowerShell - Use pipe with encoding
rustdesk.exe --help | Out-File -Encoding UTF8 output.txt
# or
rustdesk.exe --help | Set-Content output.txt

# ✅ Git Bash - Direct redirection works
./rustdesk.exe --help > output.txt
```

**Why?** Windows GUI applications (`windows_subsystem = "windows"`) are not allocated standard input/output handles by default. When a shell redirects output using `>`, it expects the program to have a valid stdout handle, which GUI apps don't have until they explicitly attach to a console.

**Workaround:**
- **PowerShell**: Use pipes (`|`) with `Out-File -Encoding UTF8` or `Set-Content`
- **CMD**: Limited support - use Git Bash or PowerShell for file output
- **Git Bash**: Works normally with direct redirection (`>`)

## License

GPL-3.0
