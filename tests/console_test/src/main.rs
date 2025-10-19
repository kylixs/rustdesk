// Console test program to verify terminal behavior on Windows
// Simulates RustDesk's GUI/CLI mode behavior
//
// This version uses the win_console library for cross-terminal support

#![cfg_attr(
    all(
        not(debug_assertions),
        target_os = "windows",
        not(feature = "cli")
    ),
    windows_subsystem = "windows"
)]

mod gui;

// Use win_console library for terminal handling
use win_console::println;

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
        // CLI mode - initialize console output handling
        win_console::init();

        match args[1].as_str() {
            "--version" => {
                println("Console Test v1.0.0");
            }
            "--help" => {
                println("Console Test - Testing Windows Console Behavior");
                println("");
                println("Usage:");
                println("  console_test.exe              GUI mode (show window)");
                println("  console_test.exe --gui        GUI mode (show window)");
                println("  console_test.exe --version    Show version");
                println("  console_test.exe --help       Show this help");
                println("  console_test.exe --test       Run test");
            }
            "--test" => {
                println("========================================");
                println("Console Test - CLI Mode");
                println("========================================");
                println("");
                println("This is a test of Windows console behavior.");
                println("Testing if terminal returns to prompt automatically.");
                println("");
                println("Build: Release (windows subsystem)");
                println("Solution: Console module");
                println("");
                println("========================================");
                println("Testing multi-line output...");
                println("Line 1");
                println("Line 2");
                println("Line 3");
                println("========================================");
            }
            _ => {
                println(&format!("Unknown command: {}", args[1]));
                println("Use --help for usage information");
            }
        }

        // Cleanup is automatic via atexit handler
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
