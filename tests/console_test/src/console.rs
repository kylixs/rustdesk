// Console Module
//
// A standalone module for handling console output in Windows GUI applications
// that need CLI support across different terminals (PowerShell, CMD, Git Bash, etc.)
//
// Usage:
//   1. Import: `use console::println;`
//   2. Call `console::init()` at program start
//   3. Use `println()` for output - automatically handles different terminals
//   4. Call `console::cleanup()` before program exit
//
// How it works:
//   - Detects the parent terminal (PowerShell, CMD, Git Bash, etc.)
//   - For PowerShell: Applies "prompt pushing" strategy to fix prompt positioning
//   - For CMD: Sends Enter key at exit to trigger new prompt
//   - For Git Bash and others: No special handling needed

#[cfg(windows)]
pub mod windows {
    use winapi::um::wincon::{AttachConsole, ATTACH_PARENT_PROCESS, GetConsoleWindow};
    use winapi::um::winuser::GetWindowThreadProcessId;
    use winapi::um::processthreadsapi::{GetCurrentProcessId, OpenProcess};
    use winapi::um::winnt::PROCESS_QUERY_LIMITED_INFORMATION;
    use winapi::um::psapi::GetModuleFileNameExW;
    use winapi::um::handleapi::CloseHandle;
    use winapi::um::processenv::GetStdHandle;
    use winapi::um::winbase::{STD_OUTPUT_HANDLE, STD_INPUT_HANDLE};
    use winapi::um::fileapi::GetFileType;
    use winapi::um::winbase::FILE_TYPE_CHAR;
    use winapi::um::wincon::{GetConsoleScreenBufferInfo, SetConsoleCursorPosition,
                             FillConsoleOutputCharacterA, WriteConsoleInputW,
                             CONSOLE_SCREEN_BUFFER_INFO, INPUT_RECORD};
    use winapi::um::wincontypes::{COORD, KEY_EVENT};
    use winapi::shared::minwindef::DWORD;
    use std::ptr::null_mut;
    use std::sync::Mutex;
    use std::io::Write;

    // Terminal type detection
    #[derive(Debug, Clone, Copy, PartialEq)]
    enum TerminalType {
        PowerShell,
        Cmd,
        GitBash,
        Other,
    }

    // Global state
    static TERMINAL_TYPE: Mutex<Option<TerminalType>> = Mutex::new(None);
    static POWERSHELL_BUFFERING: Mutex<bool> = Mutex::new(false);

    /// Initialize terminal output handling
    /// Call this at program start, before any console output
    /// Automatically registers exit handler for cleanup
    pub fn init() -> bool {
        unsafe {
            let result = AttachConsole(ATTACH_PARENT_PROCESS);
            if result != 0 {
                // Detect terminal type
                if let Some(parent_name) = get_parent_process_name() {
                    let terminal_type = match parent_name.to_lowercase().as_str() {
                        "powershell.exe" => TerminalType::PowerShell,
                        "cmd.exe" => TerminalType::Cmd,
                        "bash.exe" | "sh.exe" => TerminalType::GitBash,
                        _ => TerminalType::Other,
                    };

                    if let Ok(mut term_type) = TERMINAL_TYPE.lock() {
                        *term_type = Some(terminal_type);
                    }

                    // Enable PowerShell buffering only if stdout is console (not redirected)
                    if terminal_type == TerminalType::PowerShell && is_stdout_console() {
                        if let Ok(mut buffering) = POWERSHELL_BUFFERING.lock() {
                            *buffering = true;
                        }
                    }
                }

                // Register exit handler for automatic cleanup
                // This ensures cleanup() is called even if the user forgets
                let _ = std::panic::catch_unwind(|| {
                    extern "C" fn exit_handler() {
                        cleanup();
                    }
                    libc::atexit(exit_handler);
                });
            }
            result != 0
        }
    }

    /// Print a line with automatic terminal handling
    /// Use this instead of println!() for proper cross-terminal support
    pub fn println(text: &str) {
        if should_use_powershell_buffering() {
            // PowerShell: Apply prompt pushing strategy
            output_with_prompt_pushing(&format!("{}\n", text));
        } else {
            // All other terminals: Use normal println
            println!("{}", text);
        }
    }

    /// Print without newline
    pub fn print(text: &str) {
        if should_use_powershell_buffering() {
            // PowerShell: Apply prompt pushing strategy
            output_with_prompt_pushing(text);
        } else {
            print!("{}", text);
        }
    }

    /// Cleanup terminal state before program exit
    /// Call this at the end of your program
    pub fn cleanup() {
        use std::io::Write;
        std::io::stdout().flush().unwrap();

        if let Ok(term_type) = TERMINAL_TYPE.lock() {
            match *term_type {
                Some(TerminalType::Cmd) | Some(TerminalType::PowerShell) => {
                    // Both CMD and PowerShell need an Enter key to show the prompt
                    send_enter_key();
                }
                _ => {
                    // Git Bash and others don't need special handling
                }
            }
        }
    }

    /// Check if we should use PowerShell buffering
    fn should_use_powershell_buffering() -> bool {
        if let Ok(buffering) = POWERSHELL_BUFFERING.lock() {
            *buffering
        } else {
            false
        }
    }

    /// Output text with PowerShell prompt pushing strategy
    /// Strategy: Send Enter -> Move to previous line -> Clear -> Output -> Continue
    fn output_with_prompt_pushing(text: &str) {
        unsafe {
            let stdout_handle = GetStdHandle(STD_OUTPUT_HANDLE);
            if stdout_handle.is_null() {
                return;
            }

            let mut csbi: CONSOLE_SCREEN_BUFFER_INFO = std::mem::zeroed();
            if GetConsoleScreenBufferInfo(stdout_handle, &mut csbi) == 0 {
                return;
            }

            let current_y = csbi.dwCursorPosition.Y;

            // Send Enter to push prompt down
            send_enter_key();
            std::thread::sleep(std::time::Duration::from_millis(10));

            // Move back to previous line
            let mut pos: COORD = std::mem::zeroed();
            pos.X = 0;
            pos.Y = current_y;
            SetConsoleCursorPosition(stdout_handle, pos);

            // Clear that line
            let line_width = csbi.srWindow.Right - csbi.srWindow.Left + 1;
            let mut written: u32 = 0;
            FillConsoleOutputCharacterA(
                stdout_handle,
                b' ' as i8,
                line_width as u32,
                pos,
                &mut written,
            );

            // Output text
            SetConsoleCursorPosition(stdout_handle, pos);
            print!("{}", text);
            std::io::stdout().flush().unwrap();
        }
    }

    /// Send Enter key to console input buffer
    fn send_enter_key() {
        unsafe {
            let stdin_handle = GetStdHandle(STD_INPUT_HANDLE);
            if stdin_handle.is_null() {
                return;
            }

            let mut input_record: INPUT_RECORD = std::mem::zeroed();
            input_record.EventType = KEY_EVENT;

            let mut key_event = input_record.Event.KeyEvent_mut();
            key_event.bKeyDown = 1;
            key_event.wRepeatCount = 1;
            key_event.wVirtualKeyCode = 0x0D; // VK_RETURN
            key_event.wVirtualScanCode = 0x1C;
            key_event.uChar = unsafe { std::mem::zeroed() };
            *key_event.uChar.UnicodeChar_mut() = 0x0D;
            key_event.dwControlKeyState = 0;

            let mut written: DWORD = 0;
            WriteConsoleInputW(stdin_handle, &input_record, 1, &mut written);
        }
    }

    /// Check if stdout is a console (not redirected/piped)
    fn is_stdout_console() -> bool {
        unsafe {
            let stdout_handle = GetStdHandle(STD_OUTPUT_HANDLE);
            if stdout_handle.is_null() {
                return false;
            }
            GetFileType(stdout_handle) == FILE_TYPE_CHAR
        }
    }

    /// Get parent process name
    fn get_parent_process_name() -> Option<String> {
        unsafe {
            let console_window = GetConsoleWindow();
            if console_window.is_null() {
                return None;
            }

            let mut process_id: u32 = 0;
            GetWindowThreadProcessId(console_window, &mut process_id);

            if process_id == 0 || process_id == GetCurrentProcessId() {
                return None;
            }

            let process_handle = OpenProcess(
                PROCESS_QUERY_LIMITED_INFORMATION,
                0,
                process_id,
            );

            if process_handle.is_null() {
                return None;
            }

            let mut filename: [u16; 260] = [0; 260];
            let length = GetModuleFileNameExW(
                process_handle,
                null_mut(),
                filename.as_mut_ptr(),
                filename.len() as u32,
            );

            CloseHandle(process_handle);

            if length > 0 {
                let os_string = String::from_utf16_lossy(&filename[..length as usize]);
                let path = std::path::Path::new(&os_string);
                path.file_name()
                    .and_then(|name| name.to_str())
                    .map(|s| s.to_string())
            } else {
                None
            }
        }
    }
}

// Public API
#[cfg(windows)]
pub use windows::{init, println, print};

#[cfg(not(windows))]
pub mod stub {
    pub fn init() -> bool { true }
    pub fn println(text: &str) { println!("{}", text); }
    pub fn print(text: &str) { print!("{}", text); }
}

#[cfg(not(windows))]
pub use stub::{init, println, print};
