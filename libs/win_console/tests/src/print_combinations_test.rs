/// Print combinations test - comprehensive test for println!/print! with various \n positions
///
/// This test suite verifies that win_console correctly handles all combinations of:
/// - println!() vs print!()
/// - Leading \n, middle \n, trailing \n
/// - Single vs multiple \n
/// - Mixed print!/println! calls
///
/// Line numbering rules:
/// - Every \n increments line number by 1
/// - All lines show markers like [L1], [L2], [L3] for visual alignment
/// - Maximum 2 consecutive empty lines to keep output readable
/// - println!() adds \n at the end

/// Test 1: Basic println! - no newlines in content
pub fn test_basic_println() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test 1: Basic println! ===");
    println!("[L1] First line");
    println!("[L2] Second line");
    println!("[L3] Third line");
    println!();
}

/// Test 2: println! with leading \n
pub fn test_println_leading_newline() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test 2: println! with leading \\n ===");
    println!("[L1]\n[L2] After leading \\n");
    println!("[L3]\n[L4] Normal");
    println!();
}

/// Test 3: println! with trailing \n
pub fn test_println_trailing_newline() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test 3: println! with trailing \\n ===");
    println!("[L1] Has trailing \\n\n[L2]\n[L3]");
    println!("[L4]\n[L5] Normal");
    println!();
}

/// Test 4: println! with middle \n
pub fn test_println_middle_newline() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test 4: println! with middle \\n ===");
    println!("[L1] First\n[L2] Second");
    println!("[L3]\n[L4] Normal");
    println!();
}

/// Test 5: println! with double \n
pub fn test_println_multiple_newlines() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test 5: println! with double \\n ===");
    println!("[L1] Before\n[L2]\n[L3] After");
    println!("[L4]\n[L5] Normal");
    println!();
}

/// Test 6: Complex \n combinations
pub fn test_println_newline_combinations() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test 6: Complex \\n combinations ===");
    println!("[L1]\n[L2] Leading");
    println!("[L3]\n[L4] Middle\n[L5] Part");
    println!("[L6]\n[L7] Trail\n[L8]");
    println!("[L9]\n[L10]\n[L11] Lead+Mid\n[L12] X");
    println!();
}

/// Test 7: Basic print! without newlines
pub fn test_basic_print() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test 7: Basic print! ===");
    print!("[L1] ");
    print!("Part2 ");
    print!("Part3");
    println!();
    println!("[L2] Normal");
    println!();
}

/// Test 8: print! with \n
pub fn test_print_with_newline() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test 8: print! with \\n ===");
    print!("[L1] Part1 ");
    print!("Part2\n");
    print!("[L2] After");
    println!();
    println!("[L3]\n[L4] Next");
    println!();
}

/// Test 9: Mixed print! and println!
pub fn test_mixed_print_println() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test 9: Mixed print!/println! ===");
    print!("[L1] ");
    print!("P2 ");
    println!("P3");
    print!("[L2] ");
    println!("P2");
    println!("[L3] Normal");
    println!();
}

/// Test 10: print! with leading \n
pub fn test_print_leading_newline() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test 10: print! with leading \\n ===");
    print!("[L1] Before");
    print!("\n[L2] After");
    println!();
    println!();
}

/// Test 11: Empty println!
pub fn test_empty_println() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test 11: Empty println! ===");
    println!("[L1] Before");
    println!("[L2]");
    println!("[L3]");
    println!("[L4] After");
    println!();
}

/// Test 12: Only \n in println!
pub fn test_only_newlines() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test 12: Only \\n ===");
    println!("[L1] Before");
    println!("[L2]\n[L3]");
    println!("[L4]\n[L5]\n[L6]");
    println!("[L7]\n[L8]\n[L9] After");
    println!();
}

/// Test 13: Real-world pattern
pub fn test_realworld_pattern() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test 13: Real-world ===");
    println!("[L1] Header");
    println!("[L2] Version");
    println!("[L3]");
    println!("[L4] [Sect1]");
    println!("[L5]   Item1");
    println!("[L6]   Item2");
    println!("[L7]");
    println!("[L8] [Sect2]");
    println!();
}

/// Test 14: Long line
pub fn test_long_line() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test 14: Long line ===");
    println!("[L1] This is a very long line with lots of text to test console handling without issues");
    println!("[L2] Normal");
    println!();
}

/// Test 15: Multiple print! then println!
pub fn test_multiple_print_then_println() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test 15: Multiple print! ===");
    print!("[L1] ");
    print!("P2 ");
    print!("P3 ");
    print!("P4 ");
    println!("P5");
    println!("[L2] Next");
    println!();
}

/// Test 16: print! with \n in middle
pub fn test_print_middle_newline() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test 16: print! middle \\n ===");
    print!("[L1] First\n[L2] Second ");
    println!("Part3");
    println!("[L3] Normal");
    println!();
}

/// Test 17: Alternating print!/println!
pub fn test_alternating_print_println() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test 17: Alternating ===");
    print!("[L1] ");
    println!("P2");
    print!("[L2] ");
    println!("P2");
    print!("[L3] ");
    println!("P2");
    println!();
}

/// Test 18: Multiple \n
pub fn test_triple_newline() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test 18: Multiple \\n ===");
    println!("[L1] Before\n[L2]\n[L3]");
    println!("[L4]\n[L5] After");
    println!("[L6]\n[L7] Normal");
    println!();
}

/// Test 19: Start with \n
pub fn test_start_with_newline() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test 19: Start \\n ===");
    print!("[L1]\n[L2] After \\n");
    println!();
    print!("[L3]\n[L4]\n[L5] After \\n\\n");
    println!();
    println!();
}

/// Test 20: End with \n
pub fn test_end_with_multiple_newlines() {
    win_console::init();
    win_console::set_prompt_push_delay(20);

    println!("=== Test 20: End \\n ===");
    println!("[L1] X\n[L2]\n[L3]");
    println!("[L4]\n[L5] Y\n[L6]\n[L7]");
    println!("[L8]\n[L9]\n[L10] Z");
    println!();
}

/// Run all tests
pub fn run_all_tests() {
    println!("╔════════════════════════════════════════════════════╗");
    println!("║  Print Combinations Test Suite                    ║");
    println!("║  Line numbers: EXACT count (including empty)      ║");
    println!("║  All lines marked with [LN] for alignment         ║");
    println!("╚════════════════════════════════════════════════════╝");
    println!();

    test_basic_println();
    test_println_leading_newline();
    test_println_trailing_newline();
    test_println_middle_newline();
    test_println_multiple_newlines();
    test_println_newline_combinations();
    test_basic_print();
    test_print_with_newline();
    test_mixed_print_println();
    test_print_leading_newline();
    test_empty_println();
    test_only_newlines();
    test_realworld_pattern();
    test_long_line();
    test_multiple_print_then_println();
    test_print_middle_newline();
    test_alternating_print_println();
    test_triple_newline();
    test_start_with_newline();
    test_end_with_multiple_newlines();

    println!("╔════════════════════════════════════════════════════╗");
    println!("║  All 20 tests completed!                          ║");
    println!("║  Check: Line numbers should match exactly         ║");
    println!("╚════════════════════════════════════════════════════╝");
}
