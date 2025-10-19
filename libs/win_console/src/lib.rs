// Windows Console Library
//
// A standalone library for handling console output in Windows GUI applications
// that need CLI support across different terminals (PowerShell, CMD, Git Bash, etc.)
//
// # Features
//
// - Automatic terminal type detection (PowerShell, CMD, Git Bash)
// - Automatic prompt positioning fixes for PowerShell
// - Automatic Enter key handling for CMD
// - Support for output redirection and pipes
// - Zero configuration - just call `init()` and use `println()`
//
// # Usage
//
// ```rust
// use win_console;
//
// fn main() {
//     win_console::init();  // Initialize (auto-registers exit handler)
//
//     win_console::println("Hello, World!");
//     win_console::println("Line 2");
//
//     // Cleanup is automatic via atexit handler
// }
// ```
//
// # How it works
//
// - Detects the parent terminal (PowerShell, CMD, Git Bash, etc.)
// - For PowerShell: Applies "prompt pushing" strategy to fix prompt positioning
// - For CMD: Sends Enter key at exit to trigger new prompt
// - For Git Bash and others: No special handling needed

#[cfg(windows)]
mod windows {
    use winapi::um::wincon::{AttachConsole, ATTACH_PARENT_PROCESS, GetConsoleWindow};
    use winapi::um::consoleapi::WriteConsoleW;
    use winapi::um::winuser::GetWindowThreadProcessId;
    use winapi::um::processthreadsapi::{GetCurrentProcessId, OpenProcess};
    use winapi::um::winnt::PROCESS_QUERY_LIMITED_INFORMATION;
    use winapi::um::psapi::GetModuleFileNameExW;
    use winapi::um::handleapi::CloseHandle;
    use winapi::um::processenv::GetStdHandle;
    use winapi::um::winbase::{STD_OUTPUT_HANDLE, STD_INPUT_HANDLE};
    use winapi::um::fileapi::{GetFileType, WriteFile};
    use winapi::um::winbase::FILE_TYPE_CHAR;
    use winapi::um::wincon::{GetConsoleScreenBufferInfo, SetConsoleCursorPosition,
                             FillConsoleOutputCharacterA, WriteConsoleInputW,
                             CONSOLE_SCREEN_BUFFER_INFO, INPUT_RECORD};
    use winapi::um::wincontypes::{COORD, KEY_EVENT};
    use winapi::shared::minwindef::DWORD;
    use std::ptr::null_mut;
    use std::sync::Mutex;

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
    static PROMPT_PUSH_DELAY_MS: Mutex<u64> = Mutex::new(20); // Default 20ms delay
    static AT_LINE_START: Mutex<bool> = Mutex::new(true); // Track if cursor is at line start

    /// Initialize terminal output handling
    ///
    /// Call this at program start, before any console output.
    /// Automatically registers exit handler for cleanup.
    ///
    /// Returns `true` if successfully attached to parent console
    pub fn init() -> bool {
        unsafe {
            // Try to attach to parent console
            // Note: For windows_subsystem="windows", stdout might already be redirected by shell
            // but we won't be able to access it until after AttachConsole
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
    ///
    /// Automatically detects terminal type and applies appropriate strategy:
    /// - PowerShell: Uses "prompt pushing" to fix prompt positioning
    /// - CMD/Git Bash/Others: Uses standard println!
    pub fn println(text: &str) {
        // Check if stdout is still a console (not redirected)
        if should_use_powershell_buffering() && is_stdout_console() {
            output_with_prompt_pushing(&format!("{}\n", text));
        } else {
            // Use WriteFile for direct stdout write (supports redirection in GUI apps)
            write_to_stdout(&format!("{}\n", text));
        }
    }

    /// Print without newline with automatic terminal handling
    pub fn print(text: &str) {
        // Check if stdout is still a console (not redirected)
        if should_use_powershell_buffering() && is_stdout_console() {
            output_with_prompt_pushing(text);
        } else {
            // Use WriteFile for direct stdout write (supports redirection in GUI apps)
            write_to_stdout(text);
        }
    }

    /// Set the delay (in milliseconds) for PowerShell prompt pushing
    ///
    /// Default is 20ms. Increase if output is being overwritten by the prompt.
    /// Typical values: 20-100ms depending on system performance.
    ///
    /// # Example
    /// ```
    /// win_console::set_prompt_push_delay(50); // Use 50ms delay for slower systems
    /// ```
    pub fn set_prompt_push_delay(delay_ms: u64) {
        if let Ok(mut delay) = PROMPT_PUSH_DELAY_MS.lock() {
            *delay = delay_ms;
        }
    }

    /// Cleanup terminal state (automatically called via atexit handler)
    fn cleanup() {
        use std::io::Write;
        let _ = std::io::stdout().flush();

        if let Ok(term_type) = TERMINAL_TYPE.lock() {
            match *term_type {
                Some(TerminalType::Cmd) | Some(TerminalType::PowerShell) => {
                    send_enter_key();
                }
                _ => {}
            }
        }
    }

    fn should_use_powershell_buffering() -> bool {
        if let Ok(buffering) = POWERSHELL_BUFFERING.lock() {
            *buffering
        } else {
            false
        }
    }

    fn output_line_with_prompt_push(line_content: &str) {
        unsafe {
            let stdout_handle = GetStdHandle(STD_OUTPUT_HANDLE);
            if stdout_handle.is_null() {
                write_to_stdout(line_content);
                return;
            }

            let mut csbi: CONSOLE_SCREEN_BUFFER_INFO = std::mem::zeroed();
            if GetConsoleScreenBufferInfo(stdout_handle, &mut csbi) == 0 {
                write_to_stdout(line_content);
                return;
            }

            // Step 1: Push prompt (send Enter key)
            let current_y = csbi.dwCursorPosition.Y;
            send_enter_key();

            // Step 2: Wait for prompt to move
            let delay_ms = PROMPT_PUSH_DELAY_MS.lock().map(|d| *d).unwrap_or(20);
            std::thread::sleep(std::time::Duration::from_millis(delay_ms));

            // Step 3: Move cursor back to original position
            let mut pos: COORD = std::mem::zeroed();
            pos.X = 0;
            pos.Y = current_y;
            SetConsoleCursorPosition(stdout_handle, pos);

            // Step 4: Clear the line
            let line_width = csbi.srWindow.Right - csbi.srWindow.Left + 1;
            let mut written: u32 = 0;
            FillConsoleOutputCharacterA(
                stdout_handle,
                b' ' as i8,
                line_width as u32,
                pos,
                &mut written,
            );

            // Step 5: Reset cursor and output the line content
            SetConsoleCursorPosition(stdout_handle, pos);
            write_to_stdout(line_content);
        }
    }

    fn output_with_prompt_pushing(text: &str) {
        unsafe {
            let stdout_handle = GetStdHandle(STD_OUTPUT_HANDLE);
            if stdout_handle.is_null() {
                write_to_stdout(text);
                return;
            }

            let mut csbi: CONSOLE_SCREEN_BUFFER_INFO = std::mem::zeroed();
            if GetConsoleScreenBufferInfo(stdout_handle, &mut csbi) == 0 {
                write_to_stdout(text);
                return;
            }

            // Get global line start state
            let mut at_line_start_guard = AT_LINE_START.lock().unwrap_or_else(|e| e.into_inner());

            // Buffer to accumulate current line content
            let mut current_line = String::new();

            // Process text character by character
            for ch in text.chars() {
                if ch == '\n' {
                    // We have a complete line (might be empty for leading \n)
                    if *at_line_start_guard && !current_line.is_empty() {
                        // Output the line with prompt push
                        output_line_with_prompt_push(&current_line);
                        *at_line_start_guard = false;
                    } else if !current_line.is_empty() {
                        // We're in the middle of a line, just output accumulated content
                        write_to_stdout(&current_line);
                    } else if *at_line_start_guard {
                        // Empty line at line start (leading \n) - push prompt for empty line
                        output_line_with_prompt_push("");
                        *at_line_start_guard = false;
                    }

                    // Output the newline character
                    write_to_stdout("\n");
                    // Clear the line buffer
                    current_line.clear();
                    // Mark that we're now at the start of a new line
                    *at_line_start_guard = true;
                } else {
                    // Accumulate non-newline characters
                    current_line.push(ch);
                }
            }

            // Output any remaining content in the buffer
            if !current_line.is_empty() {
                if *at_line_start_guard {
                    // Start of a new line - push prompt
                    output_line_with_prompt_push(&current_line);
                    *at_line_start_guard = false;
                } else {
                    // Continuation of current line - just output
                    write_to_stdout(&current_line);
                }
            }
        }
    }

    fn send_enter_key() {
        unsafe {
            let stdin_handle = GetStdHandle(STD_INPUT_HANDLE);
            if stdin_handle.is_null() {
                return;
            }

            let mut input_record: INPUT_RECORD = std::mem::zeroed();
            input_record.EventType = KEY_EVENT;

            let key_event = input_record.Event.KeyEvent_mut();
            key_event.bKeyDown = 1;
            key_event.wRepeatCount = 1;
            key_event.wVirtualKeyCode = 0x0D;
            key_event.wVirtualScanCode = 0x1C;
            key_event.uChar = std::mem::zeroed();
            *key_event.uChar.UnicodeChar_mut() = 0x0D;
            key_event.dwControlKeyState = 0;

            let mut written: DWORD = 0;
            WriteConsoleInputW(stdin_handle, &input_record, 1, &mut written);
        }
    }

    fn is_stdout_console() -> bool {
        unsafe {
            let stdout_handle = GetStdHandle(STD_OUTPUT_HANDLE);
            if stdout_handle.is_null() {
                return false;
            }
            GetFileType(stdout_handle) == FILE_TYPE_CHAR
        }
    }

    /// Write directly to stdout using Windows API
    /// This works for both console output and file redirection in GUI apps
    /// Handles UTF-8 encoding correctly for Windows console
    fn write_to_stdout(text: &str) {
        unsafe {
            let stdout_handle = GetStdHandle(STD_OUTPUT_HANDLE);
            if stdout_handle.is_null() || stdout_handle == winapi::um::handleapi::INVALID_HANDLE_VALUE {
                return;
            }

            // Check if stdout is a console (not redirected)
            let is_console = GetFileType(stdout_handle) == FILE_TYPE_CHAR;

            if is_console {
                // For console output, use WriteConsoleW for proper UTF-8 handling
                let wide: Vec<u16> = text.encode_utf16().collect();
                let mut written: DWORD = 0;
                WriteConsoleW(
                    stdout_handle,
                    wide.as_ptr() as *const _,
                    wide.len() as DWORD,
                    &mut written,
                    null_mut(),
                );
            } else {
                // For file redirection, use WriteFile with UTF-8 bytes
                let bytes = text.as_bytes();
                let mut written: DWORD = 0;
                WriteFile(
                    stdout_handle,
                    bytes.as_ptr() as *const _,
                    bytes.len() as DWORD,
                    &mut written,
                    null_mut(),
                );
            }
        }
    }

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
pub use windows::{init, println, print, set_prompt_push_delay};

#[cfg(not(windows))]
pub mod stub {
    /// Stub init for non-Windows platforms
    pub fn init() -> bool { true }

    /// Stub println for non-Windows platforms
    pub fn println(text: &str) { println!("{}", text); }

    /// Stub print for non-Windows platforms
    pub fn print(text: &str) { print!("{}", text); }

    /// Stub set_prompt_push_delay for non-Windows platforms
    pub fn set_prompt_push_delay(_delay_ms: u64) { }
}

#[cfg(not(windows))]
pub use stub::{init, println, print, set_prompt_push_delay};

// Export macro for easier use in applications
#[macro_export]
macro_rules! println {
    () => { $crate::println("") };
    ($($arg:tt)*) => { $crate::println(&format!($($arg)*)) };
}

#[macro_export]
macro_rules! print {
    ($($arg:tt)*) => { $crate::print(&format!($($arg)*)) };
}
