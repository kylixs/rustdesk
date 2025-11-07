#![windows_subsystem = "windows"]

use std::{
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::atomic::Ordering,
};

use bin_reader::BinaryReader;

pub mod bin_reader;
pub mod verify;
pub mod manifest;
pub mod integrity;
#[cfg(windows)]
mod ui;

#[cfg(windows)]
const APP_METADATA: &[u8] = include_bytes!("../app_metadata.toml");
#[cfg(not(windows))]
const APP_METADATA: &[u8] = &[];
const APP_METADATA_CONFIG: &str = "meta.toml";
const META_LINE_PREFIX_TIMESTAMP: &str = "timestamp = ";
const APP_PREFIX: &str = "rustdesk";
const VERSION: &str = env!("CARGO_PKG_VERSION");  // 版本号
const APPNAME_RUNTIME_ENV_KEY: &str = "RUSTDESK_APPNAME";
#[cfg(windows)]
const SET_FOREGROUND_WINDOW_ENV_KEY: &str = "SET_FOREGROUND_WINDOW";

use std::sync::atomic::AtomicU8;
use std::sync::OnceLock;

/// Global verbose level for debug logging
/// 0 = no verbose (INFO, ERROR only)
/// 1 = -v (DEBUG, INFO, ERROR)
/// 2 = -vv (TRACE, DEBUG, INFO, ERROR)
static VERBOSE_LEVEL: AtomicU8 = AtomicU8::new(0);

/// Global start time for elapsed time tracking
static START_TIME: OnceLock<std::time::Instant> = OnceLock::new();

/// Set verbose level
pub fn set_verbose_level(level: u8) {
    VERBOSE_LEVEL.store(level, Ordering::Relaxed);
}

/// Get verbose level
pub fn get_verbose_level() -> u8 {
    VERBOSE_LEVEL.load(Ordering::Relaxed)
}

/// Check if verbose mode is enabled (for backward compatibility)
pub fn is_verbose() -> bool {
    get_verbose_level() > 0
}

/// Get start time
fn get_start_time() -> std::time::Instant {
    *START_TIME.get().expect("START_TIME not initialized")
}

/// Sanitize command-line arguments for logging by masking sensitive values
fn sanitize_args(args: &[String]) -> Vec<String> {
    const SENSITIVE_PARAMS: &[&str] = &[
        "--password",
        "--token",
        "--api-key",
        "--secret",
        "--key",
    ];

    let mut sanitized = Vec::new();
    let mut mask_next = false;

    for arg in args {
        if mask_next {
            sanitized.push("***".to_string());
            mask_next = false;
        } else if SENSITIVE_PARAMS.iter().any(|&param| arg == param) {
            sanitized.push(arg.clone());
            mask_next = true;
        } else {
            sanitized.push(arg.clone());
        }
    }

    sanitized
}

/// Cleanup old log files, keep only the most recent N files
fn cleanup_old_logs(log_dir: &Path, keep_count: usize) {
    // Collect all portable-packer log files with their modification times
    let mut log_files = Vec::new();

    if let Ok(entries) = std::fs::read_dir(log_dir) {
        for entry in entries.flatten() {
            let path = entry.path();

            // Only process portable-packer log files
            if let Some(filename) = path.file_name().and_then(|n| n.to_str()) {
                if !filename.starts_with("portable-packer-") {
                    continue;
                }
            } else {
                continue;
            }

            // Get file modification time
            if let Ok(metadata) = entry.metadata() {
                if let Ok(modified) = metadata.modified() {
                    log_files.push((path, modified));
                }
            }
        }
    }

    // If we have more than keep_count files, delete the oldest ones
    if log_files.len() > keep_count {
        // Sort by modification time (newest first)
        log_files.sort_by(|a, b| b.1.cmp(&a.1));

        // Delete files beyond keep_count
        for (path, _) in log_files.iter().skip(keep_count) {
            if let Err(e) = std::fs::remove_file(path) {
                // Silently ignore errors (file might be locked)
                let _ = e;
            }
        }
    }
}

/// Initialize logger with flexi_logger
fn init_logger() {
    use flexi_logger::*;

    // Get log directory: C:\ProgramData\RustDesk\log\portable-packer\
    let system_drive = std::env::var("SystemDrive").unwrap_or_else(|_| "C:".to_string());
    let log_dir = PathBuf::from(format!("{}\\ProgramData", system_drive))
        .join("RustDesk")
        .join("log")
        .join("portable-packer");

    // Check if log directory is writable by trying to create it
    if let Err(e) = std::fs::create_dir_all(&log_dir) {
        eprintln!("Failed to create log directory: {}", e);
        eprintln!("Log directory: {}", log_dir.display());
        eprintln!("Logging disabled. Please ensure the directory has write permissions.");
        return;  // Don't initialize logger if directory is not accessible
    }

    // Test write permission
    let test_file = log_dir.join(".write_test");
    if let Err(e) = std::fs::write(&test_file, b"test") {
        eprintln!("Log directory is not writable: {}", e);
        eprintln!("Log directory: {}", log_dir.display());
        eprintln!("Logging disabled. Please ensure the directory has write permissions.");
        return;  // Don't initialize logger if directory is not writable
    }
    let _ = std::fs::remove_file(&test_file);

    // Cleanup old log files, keep the 10 most recent
    cleanup_old_logs(&log_dir, 10);

    // Determine log level based on verbose level
    let log_level = match get_verbose_level() {
        0 => "info",      // Only INFO and ERROR
        1 => "debug",     // DEBUG, INFO, ERROR
        _ => "trace",     // TRACE, DEBUG, INFO, ERROR
    };

    // Use PID in log filename to avoid file locking conflicts between processes
    let pid = std::process::id();
    let log_basename = format!("portable-packer-{}", pid);

    if let Ok(logger) = Logger::try_with_str(log_level) {
        match logger
            .log_to_file(FileSpec::default()
                .directory(&log_dir)
                .basename(&log_basename))
            .write_mode(WriteMode::Direct)
            .format(opt_format)
            // No rotation - each process has its own log file
            // Old logs are cleaned up manually by cleanup_old_logs()
            .start()
        {
            Ok(_) => {},
            Err(e) => {
                eprintln!("Failed to initialize logger: {}", e);
                eprintln!("Log directory: {}", log_dir.display());
            }
        }
    }
}

/// Custom log format
fn opt_format(
    w: &mut dyn std::io::Write,
    now: &mut flexi_logger::DeferredNow,
    record: &log::Record,
) -> Result<(), std::io::Error> {
    write!(
        w,
        "[{}] [{}] {}",
        now.now().timestamp_millis(),
        record.level(),
        record.args()
    )
}

/// Get extraction directory: C:\ProgramData\RustDesk\bin\<version>\
fn get_extraction_dir() -> Option<PathBuf> {
    let system_drive = std::env::var("SystemDrive").unwrap_or_else(|_| "C:".to_string());
    let program_data_dir = PathBuf::from(format!("{}\\ProgramData", system_drive));
    let target_dir = program_data_dir.join(APP_PREFIX).join("bin").join(VERSION);

    // Create directory if it doesn't exist
    if let Err(e) = std::fs::create_dir_all(&target_dir) {
        log::error!("Failed to create directory {}: {}", target_dir.display(), e);
        eprintln!("Error: Failed to create directory {}: {}", target_dir.display(), e);
        return None;
    }

    log::info!("Using extraction directory: {}", target_dir.display());
    Some(target_dir)
}

fn is_timestamp_matches(dir: &Path, ts: &mut u64) -> bool {
    let Ok(app_metadata) = std::str::from_utf8(APP_METADATA) else {
        return true;
    };
    for line in app_metadata.lines() {
        if line.starts_with(META_LINE_PREFIX_TIMESTAMP) {
            if let Ok(stored_ts) = line.replace(META_LINE_PREFIX_TIMESTAMP, "").parse::<u64>() {
                *ts = stored_ts;
                break;
            }
        }
    }
    if *ts == 0 {
        return true;
    }

    if let Ok(content) = std::fs::read_to_string(dir.join(APP_METADATA_CONFIG)) {
        for line in content.lines() {
            if line.starts_with(META_LINE_PREFIX_TIMESTAMP) {
                if let Ok(stored_ts) = line.replace(META_LINE_PREFIX_TIMESTAMP, "").parse::<u64>() {
                    return *ts == stored_ts;
                }
            }
        }
    }
    false
}

fn write_meta(dir: &Path, ts: u64) {
    let meta_file = dir.join(APP_METADATA_CONFIG);
    if ts != 0 {
        let content = format!("{}{}", META_LINE_PREFIX_TIMESTAMP, ts);
        // Ignore is ok here
        let _ = std::fs::write(meta_file, content);
    }
}

/// Check if all files exist (without MD5 verification)
fn check_files_exist(reader: &BinaryReader, dir: &Path) -> bool {
    let check_start = std::time::Instant::now();

    for file in reader.files.iter() {
        let file_path = dir.join(&file.path);
        if !file_path.exists() {
            log::debug!("Missing file detected: {}", file.path);
            log::debug!("file existence check: {:.3}ms (incomplete)",
                check_start.elapsed().as_secs_f64() * 1000.0);
            return false;
        }
    }

    log::debug!("file existence check: {:.3}ms (all files present)",
        check_start.elapsed().as_secs_f64() * 1000.0);
    true
}

fn setup(
    reader: BinaryReader,
    dir: Option<PathBuf>,
    clear: bool,
    _args: &Vec<String>,
    _ui: &mut bool,
) -> Option<PathBuf> {
    let setup_start = std::time::Instant::now();

    let dir = if let Some(dir) = dir {
        dir
    } else {
        get_extraction_dir()?
    };

    let mut ts = 0;
    let check_start = std::time::Instant::now();
    let timestamp_matches = is_timestamp_matches(&dir, &mut ts);
    log::debug!("timestamp check: {:.3}ms, matches: {}",
        check_start.elapsed().as_secs_f64() * 1000.0, timestamp_matches);

    // Check if files exist (only if timestamp matches)
    let files_exist = if timestamp_matches {
        check_files_exist(&reader, &dir)
    } else {
        false
    };

    let need_setup = clear || !timestamp_matches || !files_exist;
    log::debug!("need_setup: {} (clear: {}, timestamp_matches: {}, files_exist: {})",
        need_setup, clear, timestamp_matches, files_exist);

    if need_setup {
        #[cfg(windows)]
        if _args.is_empty() {
            *_ui = true;
            ui::setup();
        }
        let remove_start = std::time::Instant::now();
        std::fs::remove_dir_all(&dir).ok();
        log::debug!("remove_dir_all: {:.3}ms",
            remove_start.elapsed().as_secs_f64() * 1000.0);

        let write_start = std::time::Instant::now();
        let mut written_count = 0;
        let mut skipped_count = 0;
        for file in reader.files.iter() {
            let file_start = std::time::Instant::now();
            if let Err(e) = file.write_to_file(&dir) {
                log::error!("Failed to write file {}: {}", file.path, e);
            }
            let elapsed = file_start.elapsed().as_secs_f64() * 1000.0;
            if elapsed > 10.0 {
                log::debug!("write file {}: {:.3}ms", file.path, elapsed);
                written_count += 1;
            } else {
                skipped_count += 1;
            }
        }
        log::debug!("write files total: {:.3}ms (written: {}, skipped: {})",
            write_start.elapsed().as_secs_f64() * 1000.0, written_count, skipped_count);

        write_meta(&dir, ts);

        #[cfg(windows)]
        {
            let broker_start = std::time::Instant::now();
            win::copy_runtime_broker(&dir);
            log::debug!("copy_runtime_broker: {:.3}ms",
                broker_start.elapsed().as_secs_f64() * 1000.0);
        }

        #[cfg(linux)]
        reader.configure_permission(&dir);

        // Generate manifest after extraction
        let manifest_start = std::time::Instant::now();
        match integrity::generate_manifest(&reader, &dir, VERSION) {
            Ok(manifest) => {
                if let Err(e) = manifest.save(&dir) {
                    log::warn!("Failed to save manifest: {}", e);
                } else {
                    log::debug!("manifest generation: {:.3}ms",
                        manifest_start.elapsed().as_secs_f64() * 1000.0);
                }
            }
            Err(e) => {
                log::warn!("Failed to generate manifest: {}", e);
            }
        }
    } else {
        log::debug!("skipping file write (timestamp matches)");

        // Verify file integrity using manifest
        if std::env::var("RUSTDESK_SKIP_INTEGRITY_CHECK").is_ok() {
            log::info!("File integrity check skipped (RUSTDESK_SKIP_INTEGRITY_CHECK set)");
        } else {
            if !verify_file_integrity(&reader, &dir) {
                log::error!("File integrity check failed - aborting");
                return None;
            }
        }
    }

    log::debug!("setup total: {:.3}ms",
        setup_start.elapsed().as_secs_f64() * 1000.0);

    Some(dir.join(&reader.exe))
}

/// Verify file integrity and restore if needed
/// Returns true if all files are OK or successfully restored, false if restoration failed
fn verify_file_integrity(reader: &BinaryReader, dir: &Path) -> bool {
    let integrity_start = std::time::Instant::now();

    // Load manifest
    let mut manifest = match manifest::FileManifest::load(dir) {
        Ok(m) => m,
        Err(e) => {
            log::warn!("Failed to load manifest: {}, regenerating", e);
            // Regenerate manifest
            match integrity::generate_manifest(reader, dir, VERSION) {
                Ok(new_manifest) => {
                    if let Err(e) = new_manifest.save(dir) {
                        log::error!("Failed to save regenerated manifest: {}", e);
                        return false;
                    }
                    new_manifest
                }
                Err(e) => {
                    log::error!("Failed to generate manifest: {}", e);
                    return false;
                }
            }
        }
    };

    // Verify files
    let verify_result = integrity::verify_files(&manifest, dir);

    if verify_result.failed.is_empty() {
        log::debug!("file integrity check: {}/{} passed in {:.3}ms",
            verify_result.passed, verify_result.total,
            integrity_start.elapsed().as_secs_f64() * 1000.0);
        return true;
    }

    log::warn!("File integrity check: {}/{} passed, {} failed",
        verify_result.passed, verify_result.total, verify_result.failed.len());

    // Restore failed files
    let (restored, failed_to_restore) = integrity::restore_files(reader, dir, &verify_result.failed);

    // Check if any files failed to restore
    if !failed_to_restore.is_empty() {
        log::error!("========================================");
        log::error!("CRITICAL: Failed to restore {} files:", failed_to_restore.len());
        for file in &failed_to_restore {
            log::error!("  - {}", file);
        }
        log::error!("========================================");
        log::error!("The application cannot continue safely.");
        log::error!("Please try the following:");
        log::error!("1. Close all running instances of the application");
        log::error!("2. Restart the portable executable");
        log::error!("3. If the problem persists, re-download the portable package");
        log::error!("========================================");

        // Print to stderr as well for visibility
        eprintln!("\n========================================");
        eprintln!("ERROR: File integrity check failed");
        eprintln!("========================================");
        eprintln!("Failed to restore {} critical files:", failed_to_restore.len());
        for file in &failed_to_restore {
            eprintln!("  - {}", file);
        }
        eprintln!("\nPossible causes:");
        eprintln!("  - Files are locked by another process");
        eprintln!("  - Insufficient disk space or permissions");
        eprintln!("  - Files were manually modified or corrupted");
        eprintln!("\nPlease close all running instances and try again.");
        eprintln!("========================================\n");

        return false;
    }

    if !restored.is_empty() {
        // Update manifest with restored files
        if let Err(e) = integrity::update_manifest_after_restore(&mut manifest, reader, dir, &restored) {
            log::warn!("Failed to update manifest metadata: {}", e);
        }

        // Save updated manifest
        if let Err(e) = manifest.save(dir) {
            log::warn!("Failed to save updated manifest: {}", e);
        }

        log::info!("file integrity check: restored {} files in {:.3}ms",
            restored.len(), integrity_start.elapsed().as_secs_f64() * 1000.0);
    }

    true
}

/// Check if running in CLI mode (any argument starting with --)
fn is_cli_mode(args: &Vec<String>) -> bool {
    args.iter().any(|arg| arg.starts_with("--"))
}

/// Exit process with elapsed time logging
fn exit_process(code: i32) -> ! {
    let elapsed = get_start_time().elapsed().as_secs_f64();
    if code == 0 {
        log::info!("Portable packer exiting, elapsed: {:.3}s", elapsed);
    } else {
        log::info!("Portable packer exiting with code {}, elapsed: {:.3}s", code, elapsed);
    }
    std::process::exit(code);
}

/// Handle --dump-manifest command
fn handle_dump_manifest() {
    println!("RustDesk Portable Manifest Viewer\n");

    // Get extraction directory
    let Some(dir) = get_extraction_dir() else {
        let err_msg = "Failed to get extraction directory";
        log::error!("{}", err_msg);
        eprintln!("{}", err_msg);
        exit_process(1);
    };

    if !dir.exists() {
        let err_msg = format!("Directory does not exist: {}", dir.display());
        log::error!("{}", err_msg);
        eprintln!("{}", err_msg);
        exit_process(1);
    }

    // Load manifest
    let manifest = match manifest::FileManifest::load(&dir) {
        Ok(m) => m,
        Err(e) => {
            let err_msg = format!("Failed to load manifest: {}", e);
            log::error!("{}", err_msg);
            eprintln!("{}", err_msg);
            exit_process(1);
        }
    };

    // Display manifest information
    println!("Manifest Information:");
    println!("  Manifest Version: {}", manifest.manifest_version);
    println!("  Portable Version: {}", manifest.portable_version);

    // Convert timestamp to readable format
    let generated_time = std::time::UNIX_EPOCH + std::time::Duration::from_secs(manifest.generated_at);
    if let Ok(datetime) = generated_time.duration_since(std::time::UNIX_EPOCH) {
        println!("  Generated At: {} (Unix timestamp: {})",
            format_timestamp(datetime.as_secs()),
            manifest.generated_at);
    }

    println!("  Total Files: {}", manifest.files.len());
    println!();

    // Display file list
    println!("File List:");
    println!("{:<60} {:>12} {:>12} {:>20} {}",
        "Path", "Size", "Modified", "Version", "MD5");
    println!("{}", "-".repeat(140));

    for file in &manifest.files {
        let version_str = file.version.as_deref().unwrap_or("N/A");
        let modified_str = format_timestamp(file.modified);

        println!("{:<60} {:>12} {:>12} {:>20} {}",
            truncate_path(&file.path, 60),
            format_size(file.size),
            modified_str,
            truncate_str(version_str, 20),
            &file.md5[..16]); // Show first 16 chars of MD5
    }

    println!();
    println!("Total: {} files", manifest.files.len());

    log::info!("Manifest dump completed");
    exit_process(0);
}

/// Format size in human-readable format
fn format_size(size: u64) -> String {
    if size < 1024 {
        format!("{} B", size)
    } else if size < 1024 * 1024 {
        format!("{:.1} KB", size as f64 / 1024.0)
    } else if size < 1024 * 1024 * 1024 {
        format!("{:.1} MB", size as f64 / (1024.0 * 1024.0))
    } else {
        format!("{:.1} GB", size as f64 / (1024.0 * 1024.0 * 1024.0))
    }
}

/// Format Unix timestamp to readable string (local timezone)
fn format_timestamp(timestamp: u64) -> String {
    use chrono::{DateTime, Utc, Local, TimeZone};

    match Utc.timestamp_opt(timestamp as i64, 0) {
        chrono::LocalResult::Single(dt) => {
            // Convert UTC to local timezone
            let local_dt: DateTime<Local> = dt.into();
            local_dt.format("%Y-%m-%d %H:%M:%S").to_string()
        }
        _ => format!("<invalid:{}>", timestamp)
    }
}

/// Truncate string to specified length
fn truncate_str(s: &str, max_len: usize) -> String {
    if s.len() <= max_len {
        s.to_string()
    } else {
        format!("{}...", &s[..max_len-3])
    }
}

/// Truncate path for display
fn truncate_path(path: &str, max_len: usize) -> String {
    if path.len() <= max_len {
        path.to_string()
    } else {
        // Try to show beginning and end
        let start_len = max_len / 2 - 2;
        let end_len = max_len - start_len - 3;
        format!("{}...{}", &path[..start_len], &path[path.len()-end_len..])
    }
}

/// Handle --verify command
fn handle_verify(args: &Vec<String>) {
    println!("RustDesk Portable Package Verifier\n");

    let quick_mode = args.contains(&"--quick".to_string());

    // Get extraction directory
    let Some(dir) = get_extraction_dir() else {
        let err_msg = "Failed to get extraction directory";
        log::error!("{}", err_msg);
        eprintln!("{}", err_msg);
        exit_process(1);
    };

    if !dir.exists() {
        let err_msg = format!("Directory does not exist: {}", dir.display());
        log::error!("{}", err_msg);
        eprintln!("{}", err_msg);
        exit_process(1);
    }

    let reader = BinaryReader::default();
    log::info!("Verification started, files: {}", reader.files.len());

    let verify_start = std::time::Instant::now();
    let result = if quick_mode {
        verify::quick_check(&reader, &dir)
    } else {
        verify::verify_directory(&reader, &dir)
    };
    let verify_elapsed = verify_start.elapsed().as_secs_f64();

    verify::print_result(&result, &dir);
    println!("  Verification Time: {:.2}s", verify_elapsed);

    let total_elapsed = get_start_time().elapsed().as_secs_f64();
    log::info!("Verification completed in {:.2}s, result: {}",
        verify_elapsed, if result.is_ok() { "OK" } else { "FAILED" });
    log::info!("Portable packer total elapsed: {:.3}s", total_elapsed);

    if !result.is_ok() {
        std::process::exit(1);
    } else {
        std::process::exit(0);
    }
}

/// Handle --fix command: verify and auto-repair files
fn handle_fix() {
    println!("RustDesk Portable Package Fixer\n");

    // Get extraction directory
    let Some(dir) = get_extraction_dir() else {
        let err_msg = "Failed to get extraction directory";
        log::error!("{}", err_msg);
        eprintln!("{}", err_msg);
        exit_process(1);
    };

    if !dir.exists() {
        let err_msg = format!("Directory does not exist: {}", dir.display());
        log::error!("{}", err_msg);
        eprintln!("{}", err_msg);
        exit_process(1);
    }

    let reader = BinaryReader::default();
    log::info!("Fix started, files: {}", reader.files.len());

    println!("Verifying files with MD5 checksums...");
    let verify_start = std::time::Instant::now();
    let result = verify::verify_directory(&reader, &dir);
    let verify_elapsed = verify_start.elapsed().as_secs_f64();

    println!("\nVerification Report:");
    println!("================================================================================");
    println!("Total files: {}", result.total_files);
    println!("Passed: {}", result.passed_files);
    println!("Failed: {}", result.failures.len());
    println!("Verification time: {:.2}s", verify_elapsed);

    if result.failures.is_empty() {
        println!("\n✓ All files verified successfully. No repairs needed.");
        log::info!("Fix completed: no repairs needed");
        exit_process(0);
    }

    // Show failed files
    println!("\nFiles requiring repair:");
    for failure in &result.failures {
        println!("  - {} ({})", failure.path,
            match failure.failure_type {
                verify::FailureType::Missing => "missing".to_string(),
                verify::FailureType::HashMismatch => "hash mismatch".to_string(),
            }
        );
    }

    // Auto-repair failed files
    println!("\nRepairing files...");
    let repair_start = std::time::Instant::now();
    let mut repaired_count = 0;
    let mut failed_repairs = Vec::new();

    for failure in &result.failures {
        print!("  Repairing: {}... ", failure.path);

        // Find file in portable data
        if let Some(file_data) = reader.files.iter().find(|f| f.path == failure.path) {
            match file_data.write_to_file(&dir) {
                Ok(()) => {
                    // Verify the repair
                    let file_path = dir.join(&failure.path);
                    match std::fs::read(&file_path) {
                        Ok(file_content) => {
                            let actual_md5 = format!("{:x}", md5::compute(&file_content));
                            let expected_md5 = String::from_utf8_lossy(file_data.md5_code).to_string();

                            if actual_md5 == expected_md5 {
                                println!("✓ OK");
                                repaired_count += 1;
                                log::info!("Repaired: {}", failure.path);
                            } else {
                                println!("✗ FAILED (MD5 mismatch after repair)");
                                failed_repairs.push(failure.path.clone());
                                log::error!("Failed to repair {}: MD5 mismatch", failure.path);
                            }
                        }
                        Err(e) => {
                            println!("✗ FAILED (cannot read: {})", e);
                            failed_repairs.push(failure.path.clone());
                            log::error!("Failed to repair {}: {}", failure.path, e);
                        }
                    }
                }
                Err(e) => {
                    println!("✗ FAILED ({})", e);
                    failed_repairs.push(failure.path.clone());
                    log::error!("Failed to repair {}: {}", failure.path, e);
                }
            }
        } else {
            println!("✗ FAILED (not found in portable data)");
            failed_repairs.push(failure.path.clone());
            log::error!("Failed to repair {}: not found in portable data", failure.path);
        }
    }

    let repair_elapsed = repair_start.elapsed().as_secs_f64();

    // Print summary
    println!("\nRepair Summary:");
    println!("================================================================================");
    println!("Repaired: {}/{}", repaired_count, result.failures.len());
    println!("Failed: {}", failed_repairs.len());
    println!("Repair time: {:.2}s", repair_elapsed);

    let total_elapsed = get_start_time().elapsed().as_secs_f64();
    log::info!("Fix completed: repaired {}/{}, elapsed: {:.3}s",
        repaired_count, result.failures.len(), total_elapsed);

    if !failed_repairs.is_empty() {
        println!("\n✗ Some files could not be repaired:");
        for path in &failed_repairs {
            println!("  - {}", path);
        }
        exit_process(1);
    } else {
        println!("\n✓ All files repaired successfully.");
        exit_process(0);
    }
}

/// Execute in CLI mode with console output support
fn execute_cli_mode(path: PathBuf, args: Vec<String>) {
    log::debug!("execute_cli_mode: started");
    log::debug!("execute_cli_mode: path={}", path.display());
    log::debug!("execute_cli_mode: args={:?}", sanitize_args(&args));

    // Setup environment
    let exe = std::env::current_exe().unwrap_or_default();
    let exe_name = exe.file_name().unwrap_or_default();
    log::debug!("execute_cli_mode: exe_name={:?}", exe_name);

    // Log portable packer loading time before executing target program
    let elapsed = get_start_time().elapsed().as_secs_f64();
    log::info!("Portable packer ready, elapsed: {:.3}s", elapsed);

    // Execute rustdesk.exe and wait for completion
    let mut cmd = Command::new(&path);
    cmd.args(&args)
        .env(APPNAME_RUNTIME_ENV_KEY, exe_name)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());

    log::debug!("execute_cli_mode: calling cmd.status()");
    // Execute and wait for completion
    match cmd.status() {
        Ok(status) => {
            log::debug!("execute_cli_mode: cmd.status() returned: {:?}", status);
            std::process::exit(status.code().unwrap_or(1));
        }
        Err(e) => {
            let err_msg = format!("Failed to execute rustdesk: {}", e);
            log::error!("execute_cli_mode: cmd.status() error: {}", e);
            eprintln!("{}", err_msg);
            std::process::exit(1);
        }
    }
}

fn use_null_stdio() -> bool {
    #[cfg(windows)]
    {
        // When running in CMD on Windows 7, using Stdio::inherit() with spawn returns an "invalid handle" error.
        // Since using Stdio::null() didn't cause any issues, and determining whether the program is launched from CMD or by double-clicking would require calling more APIs during startup, we also use Stdio::null() when launched by double-clicking on Windows 7.
        let is_windows_7 = is_windows_7();
        log::debug!("is windows7: {}", is_windows_7);
        return is_windows_7;
    }
    #[cfg(not(windows))]
    false
}

#[cfg(windows)]
fn is_windows_7() -> bool {
    use windows::Wdk::System::SystemServices::RtlGetVersion;
    use windows::Win32::System::SystemInformation::OSVERSIONINFOW;

    unsafe {
        let mut version_info = OSVERSIONINFOW::default();
        version_info.dwOSVersionInfoSize = std::mem::size_of::<OSVERSIONINFOW>() as u32;

        if RtlGetVersion(&mut version_info).is_ok() {
            // Windows 7 is version 6.1
            log::debug!("Windows version: {}.{}",
                version_info.dwMajorVersion, version_info.dwMinorVersion);
            return version_info.dwMajorVersion == 6 && version_info.dwMinorVersion == 1;
        }
    }
    false
}

fn execute(path: PathBuf, args: Vec<String>, _ui: bool) {
    log::info!("executing {}", path.display());
    // setup env
    let exe = std::env::current_exe().unwrap_or_default();
    let exe_name = exe.file_name().unwrap_or_default();
    // run executable
    let mut cmd = Command::new(path);
    cmd.args(args);
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(winapi::um::winbase::CREATE_NO_WINDOW);
        if _ui {
            cmd.env(SET_FOREGROUND_WINDOW_ENV_KEY, "1");
        }
    }

    cmd.env(APPNAME_RUNTIME_ENV_KEY, exe_name);
    if use_null_stdio() {
        cmd.stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null());
    } else {
        cmd.stdin(Stdio::inherit())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit());
    }
    let _child = cmd.spawn();

    #[cfg(windows)]
    if _ui {
        match _child {
            Ok(child) => unsafe {
                winapi::um::winuser::AllowSetForegroundWindow(child.id() as u32);
            },
            Err(e) => {
                log::error!("spawn failed: {:?}", e);
                eprintln!("{:?}", e);
            }
        }
    }
}

fn main() {
    // Initialize global start time
    START_TIME.set(std::time::Instant::now()).expect("START_TIME already set");

    let mut args = Vec::new();
    let mut arg_exe = Default::default();
    let mut i = 0;
    for arg in std::env::args() {
        if i == 0 {
            arg_exe = arg.clone();
        } else {
            args.push(arg);
        }
        i += 1;
    }

    // Check for verbose flags and set appropriate level
    // -vv or --verbose --verbose = trace level (2)
    // -v or --verbose = debug level (1)
    let verbose_count = args.iter().filter(|&arg| arg == "-v" || arg == "--verbose").count();
    let has_vv = args.iter().any(|arg| arg == "-vv");

    let verbose_level = if has_vv || verbose_count >= 2 {
        2  // trace level
    } else if verbose_count == 1 || args.contains(&"-v".to_string()) {
        1  // debug level
    } else {
        0  // info level only
    };

    set_verbose_level(verbose_level);

    // Initialize logger with flexi_logger
    init_logger();

    log::info!("Portable packer started");
    log::info!("exe: {}", arg_exe);
    log::info!("args: {:?}", sanitize_args(&args));

    let click_setup = args.is_empty() && arg_exe.to_lowercase().ends_with("install.exe");
    let quick_support = args.is_empty() && arg_exe.to_lowercase().ends_with("qs.exe");

    log::debug!("click_setup: {}, quick_support: {}", click_setup, quick_support);

    // Check if running in CLI mode
    if is_cli_mode(&args) {
        log::debug!("Mode: CLI");
        // CLI mode: use win_console for output
        // Initialize win_console to attach to parent console
        log::debug!("Calling win_console::init()");
        win_console::init();
        log::debug!("win_console::init() completed");

        // Handle portable packer specific commands
        if args.len() > 0 {
            match args[0].as_str() {
                "--help" => {
                    // Check if there's a subcommand for detailed help
                    if args.len() > 1 {
                        let command = args[1].as_str();
                        // Only handle packer commands
                        if matches!(command, "dump-manifest" | "verify" | "fix") {
                            print_command_help(command);
                            return;
                        }
                        // For non-packer commands (e.g. --help status),
                        // print header and pass through to rustdesk.exe
                        print_help_header();
                        // Don't return - let --help <arg> pass through to rustdesk.exe
                    } else {
                        // Print portable commands header, then continue
                        // to pass --help to rustdesk.exe
                        print_help_header();
                        // Don't return - let --help pass through to rustdesk.exe
                    }
                }
                "--dump-manifest" => {
                    handle_dump_manifest();
                    return;
                }
                "--verify" => {
                    handle_verify(&args);
                    return;
                }
                "--fix" => {
                    handle_fix();
                    return;
                }
                _ => {}
            }
        }

        let reader = BinaryReader::default();
        log::debug!("BinaryReader loaded: {} files", reader.files.len());
        let mut ui = false;
        if let Some(exe) = setup(
            reader,
            None,
            false,
            &args,
            &mut ui,
        ) {
            log::debug!("Setup complete, exe: {}", exe.display());
            execute_cli_mode(exe, args);
            log::debug!("CLI mode completed");
        } else {
            log::error!("Setup failed");
        }
    } else {
        log::debug!("Mode: GUI");
        // GUI mode: original logic
        let mut ui = false;
        let reader = BinaryReader::default();
        log::debug!("BinaryReader loaded: {} files", reader.files.len());
        if let Some(exe) = setup(
            reader,
            None,
            click_setup || args.contains(&"--silent-install".to_owned()),
            &args,
            &mut ui,
        ) {
            log::debug!("Setup complete, exe: {}", exe.display());
            if click_setup {
                args = vec!["--install".to_owned()];
            } else if quick_support {
                args = vec!["--quick_support".to_owned()];
            }
            execute(exe, args, ui);
            log::debug!("GUI mode completed");
        } else {
            log::error!("Setup failed");
        }
    }

    let elapsed = get_start_time().elapsed();
    log::info!("Portable packer exiting, elapsed: {:.3}s", elapsed.as_secs_f64());
}

/// Print portable commands help header
fn print_help_header() {
    println!("================================================================================");
    println!("RustDesk Portable Version {} - Additional Commands", VERSION);
    println!("================================================================================");
    println!();
    println!("PORTABLE PACKAGE COMMANDS:");
    println!("  --dump-manifest              Display manifest file contents");
    println!("  --verify [--quick]           Verify package integrity");
    println!("  --fix                        Check and fix file integrity");
    println!();
    println!("For detailed command help, use:");
    println!("  --help <command>             Example: --help verify, --help fix");
    println!();
    println!("================================================================================");
    println!();
}

/// Print detailed help for a specific command
fn print_command_help(command: &str) {
    match command {
        "dump-manifest" => {
            println!("COMMAND: --dump-manifest\n");
            println!("Display portable package manifest file contents.\n");
            println!("DESCRIPTION:");
            println!("    Shows all files tracked in the manifest with their metadata:");
            println!("    - File path");
            println!("    - File size");
            println!("    - Modification time (local timezone)");
            println!("    - File version (for executables)");
            println!("    - MD5 checksum");
            println!();
            println!("OUTPUT FORMAT:");
            println!("    Table format with columns: Path, Size, Modified, Version, MD5");
            println!();
            println!("USAGE:");
            println!("    rustdesk --dump-manifest\n");
        }
        "verify" => {
            println!("COMMAND: --verify\n");
            println!("Verify portable package integrity.\n");
            println!("DESCRIPTION:");
            println!("    Checks all files against embedded MD5 checksums to detect");
            println!("    corruption or tampering. Default mode performs full MD5");
            println!("    verification of all files.");
            println!();
            println!("OPTIONS:");
            println!("    --quick              Fast verification (skip MD5, check existence only)");
            println!();
            println!("USAGE:");
            println!("    rustdesk --verify           # Full MD5 verification");
            println!("    rustdesk --verify --quick   # Quick check (existence only)");
            println!();
            println!("EXIT CODE:");
            println!("    0    All files verified successfully");
            println!("    1    Verification failed\n");
        }
        "fix" => {
            println!("COMMAND: --fix\n");
            println!("Check and fix file integrity.\n");
            println!("DESCRIPTION:");
            println!("    Performs full MD5 verification on all files and automatically");
            println!("    repairs any corrupted or missing files from embedded data.");
            println!("    After repair, verifies the fix was successful.");
            println!();
            println!("PROCESS:");
            println!("    1. Verify all files with MD5 checksums");
            println!("    2. List files requiring repair");
            println!("    3. Auto-repair each failed file");
            println!("    4. Verify repairs were successful");
            println!("    5. Report results");
            println!();
            println!("USAGE:");
            println!("    rustdesk --fix");
            println!();
            println!("EXIT CODE:");
            println!("    0    All files OK or successfully repaired");
            println!("    1    Some files could not be repaired\n");
        }
        _ => {
            println!("Unknown command: {}\n", command);
            println!("Available commands: dump-manifest, verify, fix");
            println!("Use --help to see all commands.\n");
        }
    }
}

#[cfg(windows)]
mod win {
    use std::{fs, os::windows::process::CommandExt, path::Path, process::Command};

    // Used for privacy mode(magnifier impl).
    pub const RUNTIME_BROKER_EXE: &'static str = "C:\\Windows\\System32\\RuntimeBroker.exe";
    pub const WIN_TOPMOST_INJECTED_PROCESS_EXE: &'static str = "RuntimeBroker_rustdesk.exe";

    pub(super) fn copy_runtime_broker(dir: &Path) {
        let src = RUNTIME_BROKER_EXE;
        let tgt = WIN_TOPMOST_INJECTED_PROCESS_EXE;
        let target_file = dir.join(tgt);
        if target_file.exists() {
            if let (Ok(src_file), Ok(tgt_file)) = (fs::read(src), fs::read(&target_file)) {
                let src_md5 = format!("{:x}", md5::compute(&src_file));
                let tgt_md5 = format!("{:x}", md5::compute(&tgt_file));
                if src_md5 == tgt_md5 {
                    return;
                }
            }
        }
        let _allow_err = Command::new("taskkill")
            .args(&["/F", "/IM", "RuntimeBroker_rustdesk.exe"])
            .creation_flags(winapi::um::winbase::CREATE_NO_WINDOW)
            .output();
        let _allow_err = std::fs::copy(src, &format!("{}\\{}", dir.to_string_lossy(), tgt));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sanitize_args_password() {
        let args = vec![
            "--connect".to_string(),
            "10.49.16.50".to_string(),
            "--password".to_string(),
            "jlc@1018".to_string(),
        ];
        let sanitized = sanitize_args(&args);
        assert_eq!(sanitized, vec![
            "--connect",
            "10.49.16.50",
            "--password",
            "***",
        ]);
    }

    #[test]
    fn test_sanitize_args_token() {
        let args = vec![
            "--token".to_string(),
            "secret123".to_string(),
            "--api-key".to_string(),
            "api456".to_string(),
        ];
        let sanitized = sanitize_args(&args);
        assert_eq!(sanitized, vec![
            "--token",
            "***",
            "--api-key",
            "***",
        ]);
    }

    #[test]
    fn test_sanitize_args_no_sensitive() {
        let args = vec![
            "--connect".to_string(),
            "10.49.16.50".to_string(),
            "--port".to_string(),
            "21118".to_string(),
        ];
        let sanitized = sanitize_args(&args);
        assert_eq!(sanitized, args);
    }

    #[test]
    fn test_sanitize_args_empty() {
        let args: Vec<String> = vec![];
        let sanitized = sanitize_args(&args);
        assert_eq!(sanitized.len(), 0);
    }
}
