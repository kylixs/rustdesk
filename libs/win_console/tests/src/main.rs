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

// Import win_console macros
#[cfg(windows)]
#[macro_use]
extern crate win_console;

mod gui;
mod compat_test;
mod rustdesk_tests;
mod print_combinations_test;

// Use win_console library for terminal handling
#[cfg(windows)]
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
        // Set delay for PowerShell prompt pushing (20ms default)
        win_console::set_prompt_push_delay(20);

        match args[1].as_str() {
            "--version" => {
                println("Console Test v1.0.0");
            }
            "--help" => {
                println("Console Test - Testing Windows Console Behavior");
                println("");
                println("Usage:");
                println("  console_test.exe                GUI mode (show window)");
                println("  console_test.exe --gui          GUI mode (show window)");
                println("  console_test.exe --version      Show version");
                println("  console_test.exe --help              Show this help");
                println("  console_test.exe --test              Run basic test");
                println("  console_test.exe --compat-test       Run compatibility tests");
                println("");
                println("RustDesk CLI Scenarios (individual tests):");
                println("  console_test.exe --rd-version        Simulate: rustdesk --version");
                println("  console_test.exe --rd-build-date     Simulate: rustdesk --build-date");
                println("  console_test.exe --rd-help           Simulate: rustdesk --help");
                println("  console_test.exe --rd-status         Simulate: rustdesk --status (not running)");
                println("  console_test.exe --rd-status-running Simulate: rustdesk --status (running)");
                println("  console_test.exe --rd-status-mixed   Simulate: rustdesk --status (mixed print)");
                println("  console_test.exe --rd-list-options   Simulate: rustdesk --list-options");
                println("  console_test.exe --rustdesk-scenarios Run all RustDesk scenarios");
                println("");
                println("Print Combinations Tests:");
                println("  console_test.exe --print-test        Run all print!/println! combination tests");
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
            "--compat-test" => {
                compat_test::run_all_tests();
            }
            "--rustdesk-scenarios" => {
                rustdesk_tests::run_all_rustdesk_tests();
            }
            // Individual RustDesk CLI scenarios
            "--rd-version" => {
                rustdesk_tests::test_rustdesk_version();
            }
            "--rd-build-date" => {
                rustdesk_tests::test_rustdesk_build_date();
            }
            "--rd-help" => {
                rustdesk_tests::test_rustdesk_help();
            }
            "--rd-status" => {
                rustdesk_tests::test_rustdesk_status();
            }
            "--rd-status-running" => {
                rustdesk_tests::test_rustdesk_status_running();
            }
            "--rd-status-mixed" => {
                rustdesk_tests::test_rustdesk_status_mixed_print();
            }
            "--rd-list-options" => {
                rustdesk_tests::test_rustdesk_list_options();
            }
            "--print-test" => {
                print_combinations_test::run_all_tests();
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
