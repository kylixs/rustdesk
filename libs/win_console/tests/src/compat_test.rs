/// Compatibility tests for win_console
///
/// These tests verify that common println! patterns work correctly
/// with the PowerShell prompt pushing feature.

/// Test case 1: Leading newline in println! (should not break prompt pushing)
///
/// Issue: println!("\n...") outputs a newline BEFORE prompt pushing,
/// causing the first line to be overwritten by the prompt.
///
/// Solution: Don't use leading \n, use separate println!() calls instead.
pub fn test_leading_newline() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test: Leading Newline (INCORRECT) ===");
    println!("\nThis line has a leading \\n - it may be overwritten!");
    println!("This is the second line");

    println!();
    println!("=== Test: Separate println! (CORRECT) ===");
    println!(); // Correct way to add blank line
    println!("This line will not be overwritten");
    println!("This is the second line");
}

/// Test case 2: Mixed print! and println! calls
///
/// Issue: Using print!() without newline doesn't trigger prompt pushing
///
/// Solution: Ensure each logical output line ends with println!()
pub fn test_mixed_print_println() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test: Mixed print!/println! ===");

    // Correct usage
    println!("Single println! - works perfectly");

    // Potentially problematic
    print!("Using print! ");
    print!("multiple times ");
    println!("then println!");

    // Better approach
    let msg = format!("{} {} {}", "Build", "message", "first");
    println!("{}", msg);
}

/// Test case 3: Trailing newlines
///
/// Issue: Trailing \n in println! creates extra blank lines
///
/// Solution: Use separate println!() for blank lines
pub fn test_trailing_newline() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test: Trailing Newline ===");
    println!("Line with trailing \\n\n"); // Has \n at end
    println!("Next line - may have extra space above");

    println!();
    println!("=== Correct Way ===");
    println!("Line without trailing \\n");
    println!(); // Explicit blank line
    println!("Next line - proper spacing");
}

/// Test case 4: Empty println!
pub fn test_empty_println() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test: Empty println! ===");
    println!("Before blank line");
    println!(); // This is fine
    println!("After blank line");
}

/// Test case 5: Chinese/Unicode output
pub fn test_unicode_output() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test: Unicode/Chinese ===");
    println!("English: Hello World");
    println!("中文：你好世界");
    println!("日本語：こんにちは");
    println!("Mixed: Hello 你好 World 世界");
}

/// Test case 6: Using println! macro (recommended way)
///
/// This demonstrates using the win_console::println! macro
/// which is imported via #[macro_use] extern crate win_console
pub fn test_println_macro() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test: println! Macro (RECOMMENDED) ===");
    println!("This uses the win_console::println! macro");
    println!("It works just like std::println! but with prompt pushing");
    println!();

    // Format strings work
    let name = "RustDesk";
    let version = "1.4.3";
    println!("Program: {}", name);
    println!("Version: {}", version);
    println!("Full: {} v{}", name, version);
    println!();

    // Multiple arguments
    println!("Number: {}, Boolean: {}, Float: {:.2}", 42, true, 3.14159);

    // Debug formatting
    let items = vec!["item1", "item2", "item3"];
    println!("Items: {:?}", items);
}

/// Test case 7: First line with newline variations
///
/// Tests different ways the first line might include newlines
pub fn test_first_line_newline_variations() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test: First Line Newline Variations ===");
    println!();

    // Scenario 1: Leading newline on first println
    println!("--- Scenario 1: Leading \\n (PROBLEMATIC) ---");
    println!("\nThis starts with \\n - may be overwritten!");
    println!("Second line");
    println!();

    // Scenario 2: Correct way - separate println
    println!("--- Scenario 2: Separate println! (CORRECT) ---");
    println!();
    println!("This is the correct way");
    println!("Second line");
    println!();

    // Scenario 3: Multiple leading newlines
    println!("--- Scenario 3: Multiple leading \\n ---");
    println!("\n\nDouble leading newline - even worse!");
    println!("Second line");
    println!();

    // Scenario 4: Mixed - leading and trailing
    println!("--- Scenario 4: Both leading and trailing ---");
    println!("\nLeading and trailing\\n\n");
    println!("Next line");
    println!();

    // Scenario 5: Newline in the middle
    println!("--- Scenario 5: Newline in middle (OK) ---");
    println!("Line one\nLine two embedded");
    println!("Third line");
}

/// Test case 8: Complex mixed output patterns
///
/// Tests various combinations of print! and println! that might occur in real code
pub fn test_complex_mixed_patterns() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test: Complex Mixed Patterns ===");
    println!();

    // Pattern 1: Status indicators
    println!("--- Pattern 1: Status Indicators ---");
    print!("Loading");
    print!(".");
    print!(".");
    println!(".");
    println!("Complete!");
    println!();

    // Pattern 2: Key-value pairs
    println!("--- Pattern 2: Key-Value Display ---");
    print!("Name: ");
    println!("RustDesk");
    print!("Status: ");
    println!("Running");
    print!("Port: ");
    println!("21118");
    println!();

    // Pattern 3: Table-like output
    println!("--- Pattern 3: Table Output ---");
    println!("ID    | Name     | Status");
    println!("------|----------|--------");
    print!("001");
    print!("   | ");
    print!("Server");
    print!("   | ");
    println!("Active");
    println!();

    // Pattern 4: Progress indicator
    println!("--- Pattern 4: Progress ---");
    for i in 1..=5 {
        print!("[");
        for _j in 1..=i {
            print!("=");
        }
        for _ in i..5 {
            print!(" ");
        }
        println!("] {}%", i * 20);
    }
    println!();

    // Pattern 5: Error message with details
    println!("--- Pattern 5: Error Message ---");
    println!("Error occurred!");
    print!("  Reason: ");
    println!("Connection timeout");
    print!("  Code: ");
    println!("E1001");
}

/// Test case 9: Whitespace and formatting edge cases
pub fn test_whitespace_edge_cases() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test: Whitespace Edge Cases ===");
    println!();

    // Case 1: Empty string
    println!("--- Case 1: Empty String ---");
    println!("");
    println!("After empty string");
    println!();

    // Case 2: Only spaces
    println!("--- Case 2: Only Spaces ---");
    println!("     ");
    println!("After spaces");
    println!();

    // Case 3: Tabs
    println!("--- Case 3: Tabs ---");
    println!("\tTabbed line");
    println!("Normal line");
    println!();

    // Case 4: Multiple consecutive newlines
    println!("--- Case 4: Multiple Consecutive Newlines ---");
    println!("First");
    println!();
    println!();
    println!();
    println!("After three blank lines");
    println!();

    // Case 5: Carriage return (rarely used but possible)
    println!("--- Case 5: Special Characters ---");
    println!("Line with \\r\\n windows ending");
    println!("Line with \\n unix ending");
}

/// Test case 10: Real-world usage patterns
///
/// Simulates actual patterns used in RustDesk and similar applications
pub fn test_real_world_patterns() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test: Real-World Usage Patterns ===");
    println!();

    // Pattern 1: rustdesk --status style (BEFORE fix)
    println!("--- Pattern 1: Status Report (OLD WAY - WRONG) ---");
    println!("\n=== Service Status ===");  // Leading \n causes issue
    println!("Status: Running");
    println!("PID: 12345");
    println!();

    // Pattern 2: rustdesk --status style (AFTER fix)
    println!("--- Pattern 2: Status Report (NEW WAY - CORRECT) ---");
    println!("=== Service Status ===");  // No leading \n
    println!("Status: Running");
    println!("PID: 12345");
    println!();

    // Pattern 3: Configuration list
    println!("--- Pattern 3: Configuration List ---");
    println!("RustDesk Configuration:");
    println!("============================================================");
    println!("option1                        = value1");
    println!("option2                        = value2");
    println!("option3                        = value3");
    println!("============================================================");
    println!("Total: 3 options");
    println!();

    // Pattern 4: Chinese output (like status check)
    println!("--- Pattern 4: Chinese Status ---");
    println!("=== RustDesk 运行状态 ===");
    println!("版本: 1.4.3 (2025-10-19)");
    println!();
    println!("[服务状态]");
    println!("  ✓ 服务运行中");
    println!("  ✓ 系统服务已启用");
    println!();
    println!("[配置检查]");
    println!("  ✓ approve-mode: password");
    println!("  ✓ verification-method: use-permanent-password");
}

/// Test case 11: Stress test - many lines
pub fn test_many_lines() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test: Many Lines Output ===");
    println!("Printing 20 lines...");
    println!();

    for i in 1..=20 {
        println!("Line {}: Testing continuous output", i);
    }

    println!();
    println!("All 20 lines printed!");
}

/// Run all compatibility tests
pub fn run_all_tests() {
    println!("========================================");
    println!("win_console Compatibility Tests");
    println!("Full test suite covering various usage patterns");
    println!("========================================");
    println!();

    println!("Running basic tests...");
    println!();

    test_leading_newline();
    println!();

    test_mixed_print_println();
    println!();

    test_trailing_newline();
    println!();

    test_empty_println();
    println!();

    test_unicode_output();
    println!();

    test_println_macro();
    println!();

    println!("Running advanced tests...");
    println!();

    test_first_line_newline_variations();
    println!();

    test_complex_mixed_patterns();
    println!();

    test_whitespace_edge_cases();
    println!();

    test_real_world_patterns();
    println!();

    test_many_lines();

    println!();
    println!("========================================");
    println!("All tests completed successfully!");
    println!("Total test cases: 11");
    println!("========================================");
}
