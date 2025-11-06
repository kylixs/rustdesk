use std::{
    fs::{self},
    io::{Cursor, Read},
    path::Path,
};

#[cfg(windows)]
const BIN_DATA: &[u8] = include_bytes!("../data.bin");
#[cfg(not(windows))]
const BIN_DATA: &[u8] = &[];
// 4bytes
const LENGTH: usize = 4;
const IDENTIFIER_LENGTH: usize = 8;
const MD5_LENGTH: usize = 32;
const BUF_SIZE: usize = 4096;

pub(crate) struct BinaryData {
    pub md5_code: &'static [u8],
    // compressed gzip data
    pub raw: &'static [u8],
    pub path: String,
}

pub(crate) struct BinaryReader {
    pub files: Vec<BinaryData>,
    pub exe: String,
}

impl Default for BinaryReader {
    fn default() -> Self {
        let (files, exe) = BinaryReader::read();
        Self { files, exe }
    }
}

impl BinaryData {
    fn decompress(&self) -> Vec<u8> {
        let cursor = Cursor::new(self.raw);
        let mut decoder = brotli::Decompressor::new(cursor, BUF_SIZE);
        let mut buf = Vec::new();
        decoder.read_to_end(&mut buf).ok();
        buf
    }

    pub fn write_to_file(&self, prefix: &Path) -> std::io::Result<()> {
        let p = prefix.join(&self.path);
        if let Some(parent) = p.parent() {
            if !parent.exists() {
                fs::create_dir_all(parent)?;
            }
        }
        if p.exists() {
            // check md5
            let f = fs::read(&p).unwrap_or_default();
            let digest = format!("{:x}", md5::compute(&f));
            let md5_record = String::from_utf8_lossy(self.md5_code);
            if digest == md5_record {
                // same, skip this file
                log::trace!("skip {}", &self.path);
                return Ok(());
            } else {
                log::info!("writing {} (md5 mismatch: {} -> {})",
                    p.display(), md5_record, digest);
            }
        } else {
            log::info!("writing {} (new file)", p.display());
        }

        fs::write(&p, self.decompress())?;
        Ok(())
    }

    /// Write to file and preserve original modified time
    pub fn write_to_file_with_mtime(&self, prefix: &Path, mtime_secs: u64) -> std::io::Result<()> {
        self.write_to_file(prefix)?;

        let p = prefix.join(&self.path);

        // Set file modification time to match original
        #[cfg(windows)]
        {
            use std::time::{SystemTime, UNIX_EPOCH};
            use std::os::windows::fs::MetadataExt;

            let mtime = UNIX_EPOCH + std::time::Duration::from_secs(mtime_secs);
            if let Err(e) = filetime::set_file_mtime(&p, filetime::FileTime::from_system_time(mtime)) {
                log::warn!("Failed to set mtime for {}: {}", self.path, e);
            } else {
                log::debug!("Set mtime for {} to {}", self.path, mtime_secs);
            }
        }

        #[cfg(not(windows))]
        {
            use std::time::{SystemTime, UNIX_EPOCH};
            let mtime = UNIX_EPOCH + std::time::Duration::from_secs(mtime_secs);
            if let Err(e) = filetime::set_file_mtime(&p, filetime::FileTime::from_system_time(mtime)) {
                log::warn!("Failed to set mtime for {}: {}", self.path, e);
            }
        }

        Ok(())
    }
}

impl BinaryReader {
    fn read() -> (Vec<BinaryData>, String) {
        let mut base: usize = 0;
        let mut parsed = vec![];
        assert!(BIN_DATA.len() > IDENTIFIER_LENGTH, "bin data invalid!");
        let mut iden = String::from_utf8_lossy(&BIN_DATA[base..base + IDENTIFIER_LENGTH]);
        if iden != "rustdesk" {
            panic!("bin file is not valid!");
        }
        base += IDENTIFIER_LENGTH;
        loop {
            iden = String::from_utf8_lossy(&BIN_DATA[base..base + IDENTIFIER_LENGTH]);
            if iden == "rustdesk" {
                base += IDENTIFIER_LENGTH;
                break;
            }
            // start reading
            let mut offset = 0;
            let path_length = u32::from_be_bytes([
                BIN_DATA[base + offset],
                BIN_DATA[base + offset + 1],
                BIN_DATA[base + offset + 2],
                BIN_DATA[base + offset + 3],
            ]) as usize;
            offset += LENGTH;
            let path =
                String::from_utf8_lossy(&BIN_DATA[base + offset..base + offset + path_length])
                    .to_string();
            offset += path_length;
            // file sz
            let file_length = u32::from_be_bytes([
                BIN_DATA[base + offset],
                BIN_DATA[base + offset + 1],
                BIN_DATA[base + offset + 2],
                BIN_DATA[base + offset + 3],
            ]) as usize;
            offset += LENGTH;
            let raw = &BIN_DATA[base + offset..base + offset + file_length];
            offset += file_length;
            // md5
            let md5 = &BIN_DATA[base + offset..base + offset + MD5_LENGTH];
            offset += MD5_LENGTH;
            parsed.push(BinaryData {
                md5_code: md5,
                raw: raw,
                path: path,
            });
            base += offset;
        }
        // executable
        let executable = String::from_utf8_lossy(&BIN_DATA[base..]).to_string();
        (parsed, executable)
    }

    #[cfg(linux)]
    pub fn configure_permission(&self, prefix: &Path) {
        use std::os::unix::prelude::PermissionsExt;

        let exe_path = prefix.join(&self.exe);
        if exe_path.exists() {
            if let Ok(f) = File::open(exe_path) {
                if let Ok(meta) = f.metadata() {
                    let mut permissions = meta.permissions();
                    permissions.set_mode(0o755);
                    f.set_permissions(permissions).ok();
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_binary_reader_default() {
        // Test that BinaryReader can be created from embedded data
        let reader = BinaryReader::default();

        // Should have files
        assert!(!reader.files.is_empty(), "BinaryReader should contain files");

        // Should have exe name
        assert!(!reader.exe.is_empty(), "BinaryReader should have exe name");
    }

    #[test]
    fn test_binary_data_fields() {
        let reader = BinaryReader::default();

        // Check first file has required fields
        if let Some(first_file) = reader.files.first() {
            assert!(!first_file.path.is_empty(), "File path should not be empty");
            assert_eq!(first_file.md5_code.len(), MD5_LENGTH, "MD5 code should be 32 bytes");
            assert!(!first_file.raw.is_empty(), "Compressed data should not be empty");
        }
    }

    #[test]
    fn test_binary_data_decompress() {
        let reader = BinaryReader::default();

        // Test decompression of first file
        if let Some(first_file) = reader.files.first() {
            let decompressed = first_file.decompress();
            assert!(!decompressed.is_empty(), "Decompressed data should not be empty");
        }
    }

    #[test]
    fn test_all_files_have_valid_md5() {
        let reader = BinaryReader::default();

        for file in &reader.files {
            // MD5 should be 32 hex characters
            assert_eq!(file.md5_code.len(), MD5_LENGTH);

            // Should be valid hex
            let md5_str = String::from_utf8_lossy(file.md5_code);
            assert!(md5_str.chars().all(|c| c.is_ascii_hexdigit()),
                "MD5 should be hex: {} for file {}", md5_str, file.path);
        }
    }

    #[test]
    fn test_file_paths_format() {
        let reader = BinaryReader::default();

        for file in &reader.files {
            // Paths should start with .\ or ./
            assert!(file.path.starts_with(".\\") || file.path.starts_with("./"),
                "Path should start with .\\ or ./: {}", file.path);
        }
    }
}
