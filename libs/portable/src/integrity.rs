use crate::bin_reader::BinaryReader;
use crate::manifest::{FileManifest, FileMetadata, FileMismatch, VerifyResult};
use std::path::Path;

/// Manifest inconsistency type
#[derive(Debug)]
pub enum ManifestInconsistency {
    /// File count mismatch
    FileCountMismatch {
        manifest_count: usize,
        portable_count: usize,
    },
    /// File list mismatch
    FileListMismatch {
        missing_in_portable: Vec<String>,
        missing_in_manifest: Vec<String>,
    },
    /// MD5 checksum mismatch (portable data updated)
    MD5Mismatch {
        mismatches: Vec<(String, String, String)>, // (path, manifest_md5, portable_md5)
    },
}

impl ManifestInconsistency {
    pub fn description(&self) -> String {
        match self {
            ManifestInconsistency::FileCountMismatch { manifest_count, portable_count } => {
                format!("File count mismatch: manifest has {} files, portable has {} files",
                    manifest_count, portable_count)
            }
            ManifestInconsistency::FileListMismatch { missing_in_portable, missing_in_manifest } => {
                let mut msg = String::from("File list mismatch:\n");
                if !missing_in_portable.is_empty() {
                    msg.push_str(&format!("  - {} files in manifest but not in portable\n",
                        missing_in_portable.len()));
                }
                if !missing_in_manifest.is_empty() {
                    msg.push_str(&format!("  - {} files in portable but not in manifest\n",
                        missing_in_manifest.len()));
                }
                msg
            }
            ManifestInconsistency::MD5Mismatch { mismatches } => {
                format!("MD5 checksum mismatch for {} files (portable data updated)",
                    mismatches.len())
            }
        }
    }
}

/// Verify manifest consistency with portable data
pub fn verify_manifest_consistency(
    manifest: &FileManifest,
    reader: &BinaryReader,
) -> Result<(), ManifestInconsistency> {
    let start = std::time::Instant::now();

    // Check file count
    if manifest.files.len() != reader.files.len() {
        log::warn!("Manifest file count mismatch: manifest={}, portable={}",
            manifest.files.len(), reader.files.len());
        return Err(ManifestInconsistency::FileCountMismatch {
            manifest_count: manifest.files.len(),
            portable_count: reader.files.len(),
        });
    }

    // Build fast lookup sets
    let manifest_paths: std::collections::HashSet<&str> =
        manifest.files.iter().map(|f| f.path.as_str()).collect();
    let portable_paths: std::collections::HashSet<&str> =
        reader.files.iter().map(|f| f.path.as_str()).collect();

    // Check files in manifest but not in portable
    let missing_in_portable: Vec<_> = manifest_paths
        .difference(&portable_paths)
        .map(|s| s.to_string())
        .collect();

    // Check files in portable but not in manifest
    let missing_in_manifest: Vec<_> = portable_paths
        .difference(&manifest_paths)
        .map(|s| s.to_string())
        .collect();

    if !missing_in_portable.is_empty() || !missing_in_manifest.is_empty() {
        log::warn!("Manifest file list inconsistency detected:");
        if !missing_in_portable.is_empty() {
            log::warn!("  Files in manifest but not in portable: {:?}", missing_in_portable);
        }
        if !missing_in_manifest.is_empty() {
            log::warn!("  Files in portable but not in manifest: {:?}", missing_in_manifest);
        }

        return Err(ManifestInconsistency::FileListMismatch {
            missing_in_portable,
            missing_in_manifest,
        });
    }

    // Check file MD5 matches (prevent file content changes)
    let mut md5_mismatches = Vec::new();
    for portable_file in &reader.files {
        if let Some(manifest_file) = manifest.files.iter().find(|f| f.path == portable_file.path) {
            let portable_md5 = String::from_utf8_lossy(portable_file.md5_code).to_string();
            if manifest_file.md5 != portable_md5 {
                md5_mismatches.push((
                    portable_file.path.clone(),
                    manifest_file.md5.clone(),
                    portable_md5,
                ));
            }
        }
    }

    if !md5_mismatches.is_empty() {
        log::warn!("Manifest MD5 mismatches detected: {} files", md5_mismatches.len());
        for (path, manifest_md5, portable_md5) in &md5_mismatches {
            log::warn!("  {}: manifest={}, portable={}", path, manifest_md5, portable_md5);
        }

        return Err(ManifestInconsistency::MD5Mismatch {
            mismatches: md5_mismatches,
        });
    }

    log::debug!("Manifest consistency check passed in {:.3}ms",
        start.elapsed().as_secs_f64() * 1000.0);

    Ok(())
}

/// Generate manifest from extracted files
pub fn generate_manifest(
    reader: &BinaryReader,
    dir: &Path,
    portable_version: &str,
) -> std::io::Result<FileManifest> {
    let start = std::time::Instant::now();

    let mut manifest = FileManifest::new(portable_version.to_string());

    for file in reader.files.iter() {
        let file_path = dir.join(&file.path);

        if !file_path.exists() {
            log::warn!("File not found when generating manifest: {}", file.path);
            continue;
        }

        // Get MD5 from portable data (already calculated during packing)
        let md5 = String::from_utf8_lossy(file.md5_code).to_string();

        match FileMetadata::from_file(&file_path, file.path.clone(), md5) {
            Ok(metadata) => {
                manifest.add_file(metadata);
            }
            Err(e) => {
                log::warn!("Failed to read metadata for {}: {}", file.path, e);
            }
        }
    }

    log::info!("Manifest generated: {} files in {:.3}ms",
        manifest.files.len(), start.elapsed().as_secs_f64() * 1000.0);

    Ok(manifest)
}

/// Verify files against manifest (fast check without MD5)
pub fn verify_files(manifest: &FileManifest, dir: &Path) -> VerifyResult {
    let start = std::time::Instant::now();

    let mut result = VerifyResult {
        total: 0,
        passed: 0,
        failed: Vec::new(),
        restored: Vec::new(),
    };

    for file_meta in &manifest.files {
        // Only check executable files (.exe, .dll)
        if !is_executable(&file_meta.path) {
            continue;
        }

        result.total += 1;
        let file_path = dir.join(&file_meta.path);

        match file_meta.matches(&file_path) {
            Ok(()) => {
                result.passed += 1;
            }
            Err(reason) => {
                let actual = if file_path.exists() {
                    FileMetadata::get_actual(&file_path)
                } else {
                    None
                };

                result.failed.push(FileMismatch {
                    path: file_meta.path.clone(),
                    reason,
                    expected: file_meta.clone(),
                    actual,
                });
            }
        }
    }

    log::info!("File verification: {}/{} passed in {:.3}ms",
        result.passed, result.total, start.elapsed().as_secs_f64() * 1000.0);

    result
}

/// Restore failed files from portable data
/// Returns (restored_files, failed_to_restore)
pub fn restore_files(
    reader: &BinaryReader,
    dir: &Path,
    failed: &[FileMismatch],
) -> (Vec<String>, Vec<String>) {
    let start = std::time::Instant::now();
    let mut restored = Vec::new();
    let mut failed_to_restore = Vec::new();

    for mismatch in failed {
        log::warn!("File integrity check failed: {}", mismatch.path);
        log::warn!("  Reason: {}", mismatch.reason.as_str());
        log_mismatch_details(mismatch);
        log::warn!("  Action: Restoring from portable package");

        // Find file in portable data
        if let Some(file_data) = reader.files.iter().find(|f| f.path == mismatch.path) {
            // Restore file with original modification time
            let original_mtime = mismatch.expected.modified;

            match file_data.write_to_file_with_mtime(dir, original_mtime) {
                Ok(()) => {
                    log::info!("File written: {}", mismatch.path);

                    // Verify restoration succeeded (metadata + MD5)
                    let file_path = dir.join(&mismatch.path);

                    // Step 1: Check metadata (size and mtime)
                    match mismatch.expected.matches(&file_path) {
                        Ok(()) => {
                            // Step 2: Verify MD5 hash
                            match std::fs::read(&file_path) {
                                Ok(file_content) => {
                                    let actual_md5 = format!("{:x}", md5::compute(&file_content));
                                    let expected_md5 = String::from_utf8_lossy(file_data.md5_code).to_string();

                                    if actual_md5 == expected_md5 {
                                        log::info!("File restored and verified (metadata + MD5): {}", mismatch.path);
                                        restored.push(mismatch.path.clone());
                                    } else {
                                        log::error!("File restoration MD5 verification failed: {}", mismatch.path);
                                        log::error!("  Expected MD5: {}", expected_md5);
                                        log::error!("  Actual MD5:   {}", actual_md5);
                                        log::error!("  This indicates file corruption or incomplete write");
                                        failed_to_restore.push(mismatch.path.clone());
                                    }
                                }
                                Err(e) => {
                                    log::error!("Failed to read restored file for MD5 verification: {}: {}", mismatch.path, e);
                                    failed_to_restore.push(mismatch.path.clone());
                                }
                            }
                        }
                        Err(reason) => {
                            log::error!("File restoration metadata verification failed: {}", mismatch.path);
                            log::error!("  Verification failed: {}", reason.as_str());

                            // Get actual metadata for debugging
                            if let Some(actual) = FileMetadata::get_actual(&file_path) {
                                log::error!("  Expected: size={}, mtime={}",
                                    mismatch.expected.size, mismatch.expected.modified);
                                log::error!("  Actual:   size={}, mtime={}",
                                    actual.size, actual.modified);
                            }

                            failed_to_restore.push(mismatch.path.clone());
                        }
                    }
                }
                Err(e) => {
                    log::error!("Failed to restore file {}: {}", mismatch.path, e);
                    log::error!("  This may be caused by file being locked or insufficient permissions");
                    failed_to_restore.push(mismatch.path.clone());
                }
            }
        } else {
            log::error!("File not found in portable data: {}", mismatch.path);
            failed_to_restore.push(mismatch.path.clone());
        }
    }

    if !restored.is_empty() {
        log::info!("Successfully restored {} files in {:.3}ms",
            restored.len(), start.elapsed().as_secs_f64() * 1000.0);
    }

    if !failed_to_restore.is_empty() {
        log::error!("Failed to restore {} files", failed_to_restore.len());
    }

    (restored, failed_to_restore)
}

/// Update manifest with restored files
pub fn update_manifest_after_restore(
    manifest: &mut FileManifest,
    _reader: &BinaryReader,
    dir: &Path,
    restored: &[String],
) -> std::io::Result<()> {
    for path in restored {
        let file_path = dir.join(path);

        if !file_path.exists() {
            continue;
        }

        // Verify the file metadata matches expected (it should, since we just restored it)
        if let Some(expected) = manifest.files.iter().find(|m| &m.path == path) {
            match expected.matches(&file_path) {
                Ok(()) => {
                    log::debug!("Manifest entry for {} verified after restore", path);
                }
                Err(reason) => {
                    log::warn!("Restored file {} does not match expected metadata: {}",
                        path, reason.as_str());
                }
            }
        }
    }

    Ok(())
}

/// Check if file is executable (.exe or .dll)
fn is_executable(path: &str) -> bool {
    let path_lower = path.to_lowercase();
    path_lower.ends_with(".exe") || path_lower.ends_with(".dll")
}

/// Log detailed mismatch information
fn log_mismatch_details(mismatch: &FileMismatch) {
    log::warn!("  Expected: size={}, mtime={}, version={}",
        mismatch.expected.size,
        mismatch.expected.modified,
        mismatch.expected.version.as_deref().unwrap_or("N/A"));

    if let Some(actual) = &mismatch.actual {
        log::warn!("  Actual:   size={}, mtime={}, version={}",
            actual.size,
            actual.modified,
            actual.version.as_deref().unwrap_or("N/A"));
    } else {
        log::warn!("  Actual:   file does not exist");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_executable() {
        assert!(is_executable("rustdesk.exe"));
        assert!(is_executable("library.dll"));
        assert!(is_executable("RustDesk.EXE"));
        assert!(!is_executable("config.toml"));
        assert!(!is_executable("readme.txt"));
    }
}
