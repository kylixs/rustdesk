// Generic .COM Wrapper for Windows GUI Applications
//
// This is a console subsystem wrapper that automatically finds and launches the corresponding
// .exe file with the same base name, then waits for it to complete.
//
// ## The Problem
// Windows GUI applications (windows subsystem) don't block the parent shell when launched
// from command line. The shell returns to prompt immediately, and program output appears
// mixed with the prompt, requiring users to manually press Enter.
//
// ## The Solution
// By using a .COM wrapper (console subsystem), we leverage Windows' file extension priority:
// .COM files are executed before .EXE files. The shell waits for the .COM to complete,
// which in turn waits for the .EXE, solving the blocking problem.
//
// ## Usage
//   1. Compile this program: cargo build --release
//   2. Rename the output to <yourapp>.com (e.g., rustdesk.com, console_test.com)
//   3. Place it alongside <yourapp>.exe
//   4. When users type "<yourapp>" in command line, Windows executes .com first
//   5. The shell waits for .com to complete, which waits for .exe
//
// ## References
// - Stack Overflow: Can one executable be both console and GUI
//   https://stackoverflow.com/questions/493536/
// - Stack Overflow: Using AttachConsole, user must hit enter
//   https://stackoverflow.com/questions/1305257/
// - Microsoft Docs: AttachConsole function
//   https://learn.microsoft.com/en-us/windows/console/attachconsole
// - Real-world examples: Visual Studio (devenv.com + devenv.exe), Git for Windows
//
// ## Safety
// - Detects and prevents infinite loops (e.g., if accidentally renamed to .exe)
// - Validates target executable exists before launching
// - Properly forwards exit codes and arguments

#[cfg(windows)]
fn main() {
    use std::env;
    use std::process::{Command, exit};
    use std::ffi::OsStr;

    // Get the path of this .com wrapper
    let wrapper_path = env::current_exe().expect("Failed to get current executable path");
    let exe_dir = wrapper_path.parent().expect("Failed to get executable directory");

    // SAFETY CHECK: Verify this is actually a .com file
    // This prevents infinite loops if the wrapper is accidentally renamed to .exe
    let wrapper_ext = wrapper_path
        .extension()
        .and_then(OsStr::to_str)
        .map(|s| s.to_lowercase());

    if wrapper_ext.as_deref() != Some("com") {
        eprintln!("ERROR: This wrapper must be named with .com extension!");
        eprintln!("Current name: {}", wrapper_path.display());
        eprintln!("\nThis is a safety check to prevent infinite loops.");
        eprintln!("Please rename this file to <yourapp>.com");
        exit(2);
    }

    // Get the base name (without extension)
    let wrapper_stem = wrapper_path
        .file_stem()
        .expect("Failed to get file stem")
        .to_str()
        .expect("Failed to convert file stem to string");

    // Construct path to the corresponding .exe file
    let target_exe = exe_dir.join(format!("{}.exe", wrapper_stem));

    // SAFETY CHECK: Verify we're not calling ourselves
    // This shouldn't happen if extension check passed, but double-check
    let target_exe_canonical = target_exe.canonicalize().ok();
    let wrapper_canonical = wrapper_path.canonicalize().ok();

    if target_exe_canonical == wrapper_canonical {
        eprintln!("ERROR: Target executable is the same as this wrapper!");
        eprintln!("This would create an infinite loop.");
        eprintln!("Wrapper: {}", wrapper_path.display());
        eprintln!("Target: {}", target_exe.display());
        exit(2);
    }

    // Check if target .exe exists
    if !target_exe.exists() {
        eprintln!("Error: {} not found", target_exe.display());
        eprintln!("Expected location: {:?}", target_exe);
        eprintln!("\nThis .com wrapper requires a corresponding .exe file with the same name.");
        exit(1);
    }

    // Collect command-line arguments (skip the first one which is the program name)
    let args: Vec<String> = env::args().skip(1).collect();

    // Launch the .exe file with the same arguments
    let mut child = Command::new(&target_exe)
        .args(&args)
        .spawn()
        .unwrap_or_else(|e| {
            eprintln!("Failed to launch {}: {}", target_exe.display(), e);
            exit(1);
        });

    // Wait for the .exe to complete
    let status = child.wait().unwrap_or_else(|e| {
        eprintln!("Failed to wait for {}: {}", target_exe.display(), e);
        exit(1);
    });

    // Exit with the same code
    exit(status.code().unwrap_or(1));
}

#[cfg(not(windows))]
fn main() {
    eprintln!("This wrapper is only for Windows");
    std::process::exit(1);
}
