// GUI module for console_test
// Simple Windows GUI window for demonstration

#[cfg(windows)]
pub mod windows {
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

    /// Window procedure callback
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

                let mut rect: RECT = std::mem::zeroed();
                winapi::um::winuser::GetClientRect(hwnd, &mut rect);

                let text = "Console Test - GUI Mode\n\nThis window appears when running without CLI arguments.\n\nFor CLI mode, use:\n  --version\n  --help\n  --test\0"
                    .encode_utf16()
                    .collect::<Vec<u16>>();

                DrawTextW(
                    hdc,
                    text.as_ptr(),
                    text.len() as i32,
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

    /// Show a simple GUI window
    pub fn show_simple_window() {
        unsafe {
            let hinstance = GetModuleHandleW(null_mut());

            let class_name = WINDOW_CLASS.encode_utf16().collect::<Vec<u16>>();

            let wc = WNDCLASSW {
                style: CS_HREDRAW | CS_VREDRAW,
                lpfnWndProc: Some(window_proc),
                hInstance: hinstance,
                lpszClassName: class_name.as_ptr(),
                cbClsExtra: 0,
                cbWndExtra: 0,
                hIcon: null_mut(),
                hCursor: LoadCursorW(null_mut(), IDC_ARROW),
                hbrBackground: CreateSolidBrush(RGB(240, 240, 240)),
                lpszMenuName: null_mut(),
            };

            RegisterClassW(&wc);

            let title = WINDOW_TITLE.encode_utf16().collect::<Vec<u16>>();

            let hwnd = CreateWindowExW(
                0,
                class_name.as_ptr(),
                title.as_ptr(),
                WS_OVERLAPPEDWINDOW,
                CW_USEDEFAULT,
                CW_USEDEFAULT,
                640,
                480,
                null_mut(),
                null_mut(),
                hinstance,
                null_mut(),
            );

            if !hwnd.is_null() {
                ShowWindow(hwnd, SW_SHOW);

                let mut msg: MSG = std::mem::zeroed();
                while GetMessageW(&mut msg, null_mut(), 0, 0) > 0 {
                    TranslateMessage(&msg);
                    DispatchMessageW(&msg);
                }
            }
        }
    }
}

// Public API
#[cfg(windows)]
pub use windows::show_simple_window;

#[cfg(not(windows))]
pub fn show_simple_window() {
    eprintln!("GUI is only available on Windows");
}
