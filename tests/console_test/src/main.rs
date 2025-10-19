// Console test program to verify terminal behavior on Windows
// Simulates RustDesk's GUI/CLI mode behavior
//
// This version REPRODUCES THE PROBLEM - CLI doesn't return to prompt automatically

#![cfg_attr(
    all(
        not(debug_assertions),
        target_os = "windows",
        not(feature = "cli")
    ),
    windows_subsystem = "windows"
)]

#[cfg(windows)]
mod windows_console {
    use winapi::um::wincon::{AttachConsole, ATTACH_PARENT_PROCESS};

    pub fn attach_parent_console() -> bool {
        unsafe {
            AttachConsole(ATTACH_PARENT_PROCESS) != 0
        }
    }
}

#[cfg(windows)]
mod gui {
    use winapi::um::winuser::{
        CreateWindowExW, DefWindowProcW, DispatchMessageW, GetMessageW, LoadCursorW,
        PostQuitMessage, RegisterClassW, ShowWindow, TranslateMessage, BeginPaint,
        EndPaint, DrawTextW,
        CS_HREDRAW, CS_VREDRAW, CW_USEDEFAULT, IDC_ARROW, MSG, SW_SHOW,
        WM_DESTROY, WM_PAINT, WNDCLASSW, WS_OVERLAPPEDWINDOW, PAINTSTRUCT,
        DT_CENTER, DT_VCENTER, DT_WORDBREAK,
    };
    use winapi::um::libloaderapi::GetModuleHandleW;
    use winapi::um::wingdi::{CreateSolidBrush, RGB};
    use winapi::shared::windef::{HWND, RECT};
    use winapi::shared::minwindef::{UINT, WPARAM, LPARAM, LRESULT};
    use std::ptr::null_mut;

    const WINDOW_TITLE: &str = "Console Test - GUI Mode\0";
    const WINDOW_CLASS: &str = "ConsoleTestWindow\0";

    unsafe extern "system" fn window_proc(
        hwnd: HWND,
        msg: UINT,
        wparam: WPARAM,
        lparam: LPARAM,
    ) -> LRESULT {
        match msg {
            WM_PAINT => {
                let mut ps: PAINTSTRUCT = std::mem::zeroed();
                let hdc = BeginPaint(hwnd, &mut ps);

                let brush = CreateSolidBrush(RGB(240, 240, 240));
                winapi::um::winuser::FillRect(hdc, &ps.rcPaint, brush);

                let text = "Console Test Program\n\nThis is GUI mode.\n\nYou can close this window.";
                let mut text_utf16: Vec<u16> = text.encode_utf16().collect();
                text_utf16.push(0);

                let mut rect: RECT = std::mem::zeroed();
                rect.left = 20;
                rect.top = 20;
                rect.right = 480;
                rect.bottom = 280;

                DrawTextW(
                    hdc,
                    text_utf16.as_ptr(),
                    -1,
                    &mut rect,
                    DT_CENTER | DT_VCENTER | DT_WORDBREAK,
                );

                EndPaint(hwnd, &ps);
                0
            }
            WM_DESTROY => {
                PostQuitMessage(0);
                0
            }
            _ => DefWindowProcW(hwnd, msg, wparam, lparam),
        }
    }

    pub fn show_simple_window() {
        unsafe {
            let class_name: Vec<u16> = WINDOW_CLASS.encode_utf16().collect();
            let window_title: Vec<u16> = WINDOW_TITLE.encode_utf16().collect();

            let wc = WNDCLASSW {
                style: CS_HREDRAW | CS_VREDRAW,
                lpfnWndProc: Some(window_proc),
                cbClsExtra: 0,
                cbWndExtra: 0,
                hInstance: GetModuleHandleW(null_mut()),
                hIcon: null_mut(),
                hCursor: LoadCursorW(null_mut(), IDC_ARROW),
                hbrBackground: (6) as _,
                lpszMenuName: null_mut(),
                lpszClassName: class_name.as_ptr(),
            };

            RegisterClassW(&wc);

            let hwnd = CreateWindowExW(
                0,
                class_name.as_ptr(),
                window_title.as_ptr(),
                WS_OVERLAPPEDWINDOW,
                CW_USEDEFAULT,
                CW_USEDEFAULT,
                500,
                300,
                null_mut(),
                null_mut(),
                GetModuleHandleW(null_mut()),
                null_mut(),
            );

            if hwnd.is_null() {
                return;
            }

            ShowWindow(hwnd, SW_SHOW);

            let mut msg: MSG = std::mem::zeroed();
            while GetMessageW(&mut msg, null_mut(), 0, 0) > 0 {
                TranslateMessage(&msg);
                DispatchMessageW(&msg);
            }
        }
    }
}

#[cfg(windows)]
fn main() {
    use std::env;

    let args: Vec<String> = env::args().collect();

    // Determine if this is CLI mode
    let is_cli_mode = if args.len() > 1 {
        args[1].starts_with("--") && !matches!(args[1].as_str(), "--gui")
    } else {
        false
    };

    if is_cli_mode {
        // CLI mode - attach to parent console and output
        windows_console::attach_parent_console();

        match args[1].as_str() {
            "--version" => {
                println!("Console Test v1.0.0");
            }
            "--help" => {
                println!("Console Test - Testing Windows Console Behavior");
                println!();
                println!("Usage:");
                println!("  console_test.exe              GUI mode (show window)");
                println!("  console_test.exe --gui        GUI mode (show window)");
                println!("  console_test.exe --version    Show version");
                println!("  console_test.exe --help       Show this help");
                println!("  console_test.exe --test       Run test");
            }
            "--test" => {
                println!("========================================");
                println!("Console Test - CLI Mode");
                println!("========================================");
                println!();
                println!("This is a test of Windows console behavior.");
                println!("Testing if terminal returns to prompt automatically.");
                println!();
                println!("Build: Release (windows subsystem)");
                println!("========================================");
            }
            _ => {
                println!("Unknown command: {}", args[1]);
                println!("Use --help for usage information");
            }
        }

        // Flush output
        use std::io::Write;
        std::io::stdout().flush().unwrap();
    } else {
        // GUI mode - show window
        gui::show_simple_window();
    }
}

#[cfg(not(windows))]
fn main() {
    eprintln!("This test is only for Windows platform");
    std::process::exit(1);
}
