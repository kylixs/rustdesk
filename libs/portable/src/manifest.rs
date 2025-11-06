use serde::{Deserialize, Serialize};
use std::path::Path;
use std::time::SystemTime;

/// Manifest file name
pub const MANIFEST_FILE: &str = ".rustdesk_manifest.bin";

/// Current manifest format version
const MANIFEST_VERSION: u32 = 1;

/// File manifest containing metadata for all extracted files
#[derive(Debug, Serialize, Deserialize)]
pub struct FileManifest {
    /// Manifest format version
    pub manifest_version: u32,
    /// Generation timestamp (Unix seconds)
    pub generated_at: u64,
    /// Portable package version
    pub portable_version: String,
    /// List of file metadata
    pub files: Vec<FileMetadata>,
}

/// Metadata for a single file
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileMetadata {
    /// Relative path (using / separator)
    pub path: String,
    /// File size in bytes
    pub size: u64,
    /// Last modified time (Unix seconds)
    pub modified: u64,
    /// Version string (optional, only for exe/dll)
    pub version: Option<String>,
    /// MD5 hash (from portable data, not recalculated)
    pub md5: String,
}

/// Verification result
#[derive(Debug)]
pub struct VerifyResult {
    /// Total files checked
    pub total: usize,
    /// Files that passed verification
    pub passed: usize,
    /// Files that failed verification
    pub failed: Vec<FileMismatch>,
    /// Files that were restored
    pub restored: Vec<String>,
}

/// File mismatch details
#[derive(Debug, Clone)]
pub struct FileMismatch {
    pub path: String,
    pub reason: MismatchReason,
    pub expected: FileMetadata,
    pub actual: Option<FileMetadata>,
}

/// Reason for file mismatch
#[derive(Debug, Clone)]
pub enum MismatchReason {
    Missing,
    SizeMismatch,
    TimeMismatch,
    VersionMismatch,
}

impl FileManifest {
    /// Create a new manifest
    pub fn new(portable_version: String) -> Self {
        let now = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        Self {
            manifest_version: MANIFEST_VERSION,
            generated_at: now,
            portable_version,
            files: Vec::new(),
        }
    }

    /// Add file metadata to manifest
    pub fn add_file(&mut self, metadata: FileMetadata) {
        self.files.push(metadata);
    }

    /// Save manifest to file with CRC32 checksum
    pub fn save(&self, dir: &Path) -> std::io::Result<()> {
        let manifest_path = dir.join(MANIFEST_FILE);

        // Serialize to binary using bincode
        let data = bincode::serialize(self)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;

        // Calculate CRC32
        let mut hasher = crc32fast::Hasher::new();
        hasher.update(&data);
        let checksum = hasher.finalize();

        // Write: [4 bytes CRC32] + [binary data]
        let mut file_data = Vec::with_capacity(4 + data.len());
        file_data.extend_from_slice(&checksum.to_le_bytes());
        file_data.extend_from_slice(&data);

        let file_data_len = file_data.len();
        std::fs::write(&manifest_path, file_data)?;

        log::info!("Manifest saved: {} ({} files, {} bytes)",
            manifest_path.display(), self.files.len(), file_data_len);

        Ok(())
    }

    /// Load manifest from file and verify CRC32
    pub fn load(dir: &Path) -> std::io::Result<Self> {
        let manifest_path = dir.join(MANIFEST_FILE);

        if !manifest_path.exists() {
            return Err(std::io::Error::new(
                std::io::ErrorKind::NotFound,
                "Manifest file not found",
            ));
        }

        let file_data = std::fs::read(&manifest_path)?;

        if file_data.len() < 4 {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "Manifest file too small",
            ));
        }

        // Read CRC32
        let stored_checksum = u32::from_le_bytes([
            file_data[0],
            file_data[1],
            file_data[2],
            file_data[3],
        ]);

        let data = &file_data[4..];

        // Verify CRC32
        let mut hasher = crc32fast::Hasher::new();
        hasher.update(data);
        let calculated_checksum = hasher.finalize();

        if stored_checksum != calculated_checksum {
            log::warn!("Manifest CRC32 mismatch: stored={:08x}, calculated={:08x}",
                stored_checksum, calculated_checksum);
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "Manifest CRC32 verification failed",
            ));
        }

        // Deserialize
        let manifest: FileManifest = bincode::deserialize(data)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;

        log::info!("Manifest loaded: {} ({} files)",
            manifest_path.display(), manifest.files.len());

        Ok(manifest)
    }

    /// Check if manifest file exists
    pub fn exists(dir: &Path) -> bool {
        dir.join(MANIFEST_FILE).exists()
    }
}

impl FileMetadata {
    /// Create metadata from file on disk
    pub fn from_file(path: &Path, relative_path: String, md5: String) -> std::io::Result<Self> {
        let metadata = std::fs::metadata(path)?;

        let size = metadata.len();
        let modified = metadata.modified()?
            .duration_since(SystemTime::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        // Get version for exe/dll files
        let version = if path.extension().and_then(|s| s.to_str())
            .map(|ext| ext.eq_ignore_ascii_case("exe") || ext.eq_ignore_ascii_case("dll"))
            .unwrap_or(false)
        {
            get_file_version(path)
        } else {
            None
        };

        Ok(Self {
            path: relative_path,
            size,
            modified,
            version,
            md5,
        })
    }

    /// Check if file matches this metadata (fast check without MD5)
    /// Returns Ok(()) if matches, Err(reason) if not
    ///
    /// Note: Skip version verification during startup for performance.
    /// File size + modified time is sufficient to detect modifications.
    pub fn matches(&self, path: &Path) -> Result<(), MismatchReason> {
        // Check existence
        if !path.exists() {
            return Err(MismatchReason::Missing);
        }

        let metadata = std::fs::metadata(path).map_err(|_| MismatchReason::Missing)?;

        // Check size (fast, < 1ms)
        if metadata.len() != self.size {
            return Err(MismatchReason::SizeMismatch);
        }

        // Check modified time (fast, < 1ms)
        let modified = metadata.modified()
            .map_err(|_| MismatchReason::TimeMismatch)?
            .duration_since(SystemTime::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        if modified != self.modified {
            return Err(MismatchReason::TimeMismatch);
        }

        // Skip version check for performance (GetFileVersionInfoW is slow for large files)
        // File size + mtime combination is sufficient to detect modifications

        Ok(())
    }

    /// Get current metadata from file
    pub fn get_actual(path: &Path) -> Option<Self> {
        let metadata = std::fs::metadata(path).ok()?;
        let size = metadata.len();
        let modified = metadata.modified().ok()?
            .duration_since(SystemTime::UNIX_EPOCH)
            .unwrap()
            .as_secs();
        let version = get_file_version(path);

        Some(Self {
            path: path.to_string_lossy().to_string(),
            size,
            modified,
            version,
            md5: String::new(),
        })
    }
}

impl MismatchReason {
    pub fn as_str(&self) -> &str {
        match self {
            MismatchReason::Missing => "file missing",
            MismatchReason::SizeMismatch => "size mismatch",
            MismatchReason::TimeMismatch => "modified time mismatch",
            MismatchReason::VersionMismatch => "version mismatch",
        }
    }
}

/// Get file version from Windows PE file (exe/dll)
#[cfg(windows)]
fn get_file_version(path: &Path) -> Option<String> {
    use std::ffi::OsStr;
    use std::os::windows::ffi::OsStrExt;

    // Convert path to wide string
    let path_wide: Vec<u16> = OsStr::new(path)
        .encode_wide()
        .chain(Some(0))
        .collect();

    unsafe {
        use winapi::um::winver::{GetFileVersionInfoSizeW, GetFileVersionInfoW, VerQueryValueW};
        use winapi::shared::minwindef::LPVOID;

        // Get version info size
        let size = GetFileVersionInfoSizeW(path_wide.as_ptr(), std::ptr::null_mut());
        if size == 0 {
            return None;
        }

        // Allocate buffer and get version info
        let mut buffer: Vec<u8> = vec![0; size as usize];
        if GetFileVersionInfoW(
            path_wide.as_ptr(),
            0,
            size,
            buffer.as_mut_ptr() as LPVOID,
        ) == 0
        {
            return None;
        }

        // Query ProductVersion string
        // Try different language/codepage combinations
        let sub_blocks = [
            "\\StringFileInfo\\040904b0\\ProductVersion",  // English (US)
            "\\StringFileInfo\\040904e4\\ProductVersion",  // English (US), Unicode
            "\\StringFileInfo\\000004b0\\ProductVersion",  // Language neutral
        ];

        for sub_block in &sub_blocks {
            let sub_block_wide: Vec<u16> = OsStr::new(sub_block)
                .encode_wide()
                .chain(Some(0))
                .collect();

            let mut value_ptr: LPVOID = std::ptr::null_mut();
            let mut value_len: u32 = 0;

            if VerQueryValueW(
                buffer.as_ptr() as LPVOID,
                sub_block_wide.as_ptr(),
                &mut value_ptr,
                &mut value_len,
            ) != 0 && !value_ptr.is_null() && value_len > 0
            {
                // Convert wide string to Rust String
                let version_slice = std::slice::from_raw_parts(
                    value_ptr as *const u16,
                    (value_len as usize).saturating_sub(1), // Exclude null terminator
                );
                let version = String::from_utf16_lossy(version_slice);
                let version = version.trim_end_matches('\0').trim();

                if !version.is_empty() {
                    return Some(version.to_string());
                }
            }
        }
    }

    None
}

#[cfg(not(windows))]
fn get_file_version(_path: &Path) -> Option<String> {
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_manifest_create() {
        let manifest = FileManifest::new("1.4.3-jlc20".to_string());
        assert_eq!(manifest.manifest_version, MANIFEST_VERSION);
        assert_eq!(manifest.portable_version, "1.4.3-jlc20");
        assert!(manifest.files.is_empty());
    }

    #[test]
    fn test_file_metadata() {
        let metadata = FileMetadata {
            path: "rustdesk.exe".to_string(),
            size: 12345678,
            modified: 1699500000,
            version: Some("1.4.3-jlc20+20251106-0913".to_string()),
            md5: "abcd1234".to_string(),
        };

        assert_eq!(metadata.path, "rustdesk.exe");
        assert_eq!(metadata.size, 12345678);
    }

    #[test]
    fn test_mismatch_reason() {
        assert_eq!(MismatchReason::Missing.as_str(), "file missing");
        assert_eq!(MismatchReason::SizeMismatch.as_str(), "size mismatch");
    }
}
