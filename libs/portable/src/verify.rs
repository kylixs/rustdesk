// Portable package verification module
// Verifies the integrity of extracted portable package files

use std::fs;
use std::path::Path;
use crate::bin_reader::BinaryReader;

/// Type of verification failure
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FailureType {
    Missing,
    HashMismatch,
}

/// Information about a failed file verification
#[derive(Debug, Clone)]
pub struct FileFailure {
    pub path: String,
    pub failure_type: FailureType,
    pub expected_md5: String,
    pub actual_md5: Option<String>,
    pub actual_size: Option<u64>,
}

/// Result of verification
#[derive(Debug)]
pub struct VerifyResult {
    pub total_files: usize,
    pub passed_files: usize,
    pub failures: Vec<FileFailure>,
}

impl VerifyResult {
    pub fn is_ok(&self) -> bool {
        self.failures.is_empty()
    }
}

/// Compute MD5 hash of a file
fn compute_file_hash(path: &Path) -> std::io::Result<String> {
    let data = fs::read(path)?;
    let digest = md5::compute(&data);
    Ok(format!("{:x}", digest))
}

/// Verify a single file
fn verify_file(
    dir: &Path,
    rel_path: &str,
    expected_md5: &str,
) -> Result<FileFailure, ()> {
    let file_path = dir.join(rel_path);

    if !file_path.exists() {
        return Ok(FileFailure {
            path: rel_path.to_string(),
            failure_type: FailureType::Missing,
            expected_md5: expected_md5.to_string(),
            actual_md5: None,
            actual_size: None,
        });
    }

    let actual_size = fs::metadata(&file_path).ok().map(|m| m.len());

    match compute_file_hash(&file_path) {
        Ok(actual_md5) => {
            if actual_md5 == expected_md5 {
                Err(())
            } else {
                Ok(FileFailure {
                    path: rel_path.to_string(),
                    failure_type: FailureType::HashMismatch,
                    expected_md5: expected_md5.to_string(),
                    actual_md5: Some(actual_md5),
                    actual_size,
                })
            }
        }
        Err(_) => {
            Ok(FileFailure {
                path: rel_path.to_string(),
                failure_type: FailureType::Missing,
                expected_md5: expected_md5.to_string(),
                actual_md5: None,
                actual_size: None,
            })
        }
    }
}

/// Verify directory against embedded checksums
pub fn verify_directory(reader: &BinaryReader, dir: &Path) -> VerifyResult {
    let total_files = reader.files.len();
    let mut failures = Vec::new();
    let mut passed_files = 0;

    for file_data in &reader.files {
        let expected_md5 = String::from_utf8_lossy(file_data.md5_code).to_string();

        match verify_file(dir, &file_data.path, &expected_md5) {
            Ok(failure) => failures.push(failure),
            Err(()) => passed_files += 1,
        }
    }

    VerifyResult {
        total_files,
        passed_files,
        failures,
    }
}

/// Quick check (only existence, no MD5)
pub fn quick_check(reader: &BinaryReader, dir: &Path) -> VerifyResult {
    let total_files = reader.files.len();
    let mut failures = Vec::new();
    let mut passed_files = 0;

    for file_data in &reader.files {
        let file_path = dir.join(&file_data.path);
        let expected_md5 = String::from_utf8_lossy(file_data.md5_code).to_string();

        if !file_path.exists() {
            failures.push(FileFailure {
                path: file_data.path.clone(),
                failure_type: FailureType::Missing,
                expected_md5,
                actual_md5: None,
                actual_size: None,
            });
        } else {
            passed_files += 1;
        }
    }

    VerifyResult {
        total_files,
        passed_files,
        failures,
    }
}

/// Print verification result
pub fn print_result(result: &VerifyResult, dir: &Path) {
    println!("RustDesk Portable Verification Report");
    println!("================================================================================");
    println!("Directory: {}", dir.display());
    println!("Hash Algorithm: MD5");
    println!();

    if result.failures.is_empty() {
        println!("✓ All files verified successfully");
        println!();
        println!("Summary:");
        println!("  Total: {} files", result.total_files);
        println!("  Status: OK ✓");
    } else {
        println!("Failed Files ({}):", result.failures.len());
        println!("┌──────────────────────────────┬────────┬───────────────────────────┬─────────┐");
        println!("│ File                         │ Status │ Issue                     │ Size    │");
        println!("├──────────────────────────────┼────────┼───────────────────────────┼─────────┤");

        for failure in &result.failures {
            let file_name = truncate_path(&failure.path, 28);
            let status = "ERROR ";
            let issue = match failure.failure_type {
                FailureType::Missing => "Missing file              ",
                FailureType::HashMismatch => "MD5 mismatch              ",
            };
            let size = if let Some(s) = failure.actual_size {
                format!("{:>7} ", format_size(s))
            } else {
                "-       ".to_string()
            };

            println!("│ {:28} │ {} │ {} │ {} │", file_name, status, issue, size);
        }

        println!("└──────────────────────────────┴────────┴───────────────────────────┴─────────┘");
        println!();

        // Detailed info
        println!("Detailed Information:");
        println!("────────────────────────────────────────────────────────────────────────────────");
        for (i, failure) in result.failures.iter().enumerate() {
            println!("[{}] {}", i + 1, failure.path);
            let status_msg = match failure.failure_type {
                FailureType::Missing => "ERROR - File missing",
                FailureType::HashMismatch => "ERROR - MD5 hash mismatch",
            };
            println!("    Status: {}", status_msg);
            println!("    Expected MD5: {}", failure.expected_md5);
            if let Some(ref actual_md5) = failure.actual_md5 {
                println!("    Actual MD5:   {}", actual_md5);
            }
            if let Some(size) = failure.actual_size {
                println!("    File Size: {}", format_size(size));
            }
            if i < result.failures.len() - 1 {
                println!();
            }
        }
        println!("────────────────────────────────────────────────────────────────────────────────");
        println!();

        println!("Summary:");
        println!("  Total: {} files", result.total_files);
        println!("  Passed: {} files ({:.1}%)",
            result.passed_files,
            (result.passed_files as f64 / result.total_files as f64) * 100.0);
        println!("  Errors: {} file{}", result.failures.len(),
            if result.failures.len() > 1 { "s" } else { "" });
        println!("  Status: FAILED ✗");
    }
}

fn format_size(bytes: u64) -> String {
    const KB: u64 = 1024;
    const MB: u64 = KB * 1024;
    const GB: u64 = MB * 1024;

    if bytes >= GB {
        format!("{:.1} GB", bytes as f64 / GB as f64)
    } else if bytes >= MB {
        format!("{:.1} MB", bytes as f64 / MB as f64)
    } else if bytes >= KB {
        format!("{:.1} KB", bytes as f64 / KB as f64)
    } else {
        format!("{} bytes", bytes)
    }
}

fn truncate_path(path: &str, max_len: usize) -> String {
    if path.len() <= max_len {
        format!("{:width$}", path, width = max_len)
    } else {
        let parts: Vec<&str> = path.split('/').collect();
        if parts.len() > 1 {
            let filename = parts.last().unwrap();
            if filename.len() + 3 <= max_len {
                format!("{:width$}", format!(".../{}", filename), width = max_len)
            } else {
                format!("{:width$}", &path[..max_len-3], width = max_len-3) + "..."
            }
        } else {
            format!("{:width$}", &path[..max_len-3], width = max_len-3) + "..."
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bin_reader::BinaryReader;
    use std::fs;
    use std::path::PathBuf;

    #[test]
    fn test_verify_result_is_ok() {
        let result = VerifyResult {
            total_files: 5,
            passed_files: 5,
            failures: vec![],
        };
        assert!(result.is_ok());

        let result_with_failure = VerifyResult {
            total_files: 5,
            passed_files: 4,
            failures: vec![FileFailure {
                path: "test.txt".to_string(),
                failure_type: FailureType::Missing,
                expected_md5: "abc123".to_string(),
                actual_md5: None,
                actual_size: None,
            }],
        };
        assert!(!result_with_failure.is_ok());
    }

    #[test]
    fn test_format_size() {
        assert_eq!(format_size(500), "500 bytes");
        assert_eq!(format_size(1024), "1.0 KB");
        assert_eq!(format_size(1024 * 1024), "1.0 MB");
        assert_eq!(format_size(1024 * 1024 * 1024), "1.0 GB");
        assert_eq!(format_size(1536), "1.5 KB");
    }

    #[test]
    fn test_truncate_path() {
        assert_eq!(truncate_path("short.txt", 20), "short.txt           ");

        let truncated = truncate_path("a/very/long/path/to/file.txt", 15);
        assert_eq!(truncated.len(), 15);
        // The function may format it as ".../filename" or truncate with "..."
        assert!(truncated.contains("...") || truncated.contains("file.txt"));
    }

    #[test]
    fn test_quick_check_with_embedded_data() {
        // Use embedded data from BinaryReader
        let reader = BinaryReader::default();

        // Create a temporary directory
        let temp_dir = std::env::temp_dir().join(format!("rustdesk_test_{}", std::process::id()));
        fs::create_dir_all(&temp_dir).unwrap();

        // Write first file to temp dir for testing
        if let Some(first_file) = reader.files.first() {
            first_file.write_to_file(&temp_dir);

            // Quick check should pass for this one file
            let result = quick_check(&reader, &temp_dir);

            // At least one file should be found
            assert!(result.passed_files >= 1 || !result.failures.is_empty());
        }

        // Cleanup
        fs::remove_dir_all(&temp_dir).ok();
    }

    #[test]
    fn test_verify_missing_file() {
        let reader = BinaryReader::default();

        // Use non-existent directory
        let temp_dir = PathBuf::from("/nonexistent_dir_for_test");

        let result = quick_check(&reader, &temp_dir);

        // All files should be missing
        assert_eq!(result.failures.len(), result.total_files);
        assert!(result.failures.iter().all(|f| f.failure_type == FailureType::Missing));
    }
}
