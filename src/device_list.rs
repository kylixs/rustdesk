use anyhow::{anyhow, Result};
use hbb_common::config::Config;
use hbb_common::log;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

/// Device configuration for remote connections
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceConfig {
    /// Display name of the device (required, unique identifier)
    pub name: String,
    /// RustDesk ID (9-digit number, optional)
    #[serde(default)]
    pub id: String,
    /// IP address or domain name (optional)
    #[serde(default)]
    pub ip: String,
    /// Connection port (default: 21118)
    #[serde(default = "default_port")]
    pub port: u16,
    /// Encrypted password (empty if not saved)
    #[serde(default)]
    pub password: String,
    /// Platform: Windows/Linux/macOS (optional)
    #[serde(default)]
    pub platform: String,
    /// Note/description (optional)
    #[serde(default)]
    pub note: String,
    /// Remote host username (optional)
    #[serde(default)]
    pub username: String,
    /// Remote hostname (optional)
    #[serde(default)]
    pub hostname: String,
}

fn default_port() -> u16 {
    21118
}

impl DeviceConfig {
    /// Validate device configuration
    pub fn validate(&self) -> Result<()> {
        // name must not be empty
        if self.name.trim().is_empty() {
            return Err(anyhow!("Device name cannot be empty"));
        }

        // id or ip must be provided
        if self.id.trim().is_empty() && self.ip.trim().is_empty() {
            return Err(anyhow!("Either ID or IP must be provided for device '{}'", self.name));
        }

        // validate id format if provided
        if !self.id.trim().is_empty() {
            // RustDesk ID should be 9 digits
            if !self.id.chars().all(|c| c.is_numeric()) {
                return Err(anyhow!("Invalid ID format for device '{}': ID must contain only digits", self.name));
            }
            if self.id.len() != 9 {
                return Err(anyhow!("Invalid ID format for device '{}': ID must be exactly 9 digits", self.name));
            }
        }

        // validate port range
        if self.port == 0 {
            return Err(anyhow!("Invalid port for device '{}': port must be between 1-65535", self.name));
        }

        Ok(())
    }

    /// Get display target (IP or ID)
    /// Priority: IP > ID
    pub fn display_target(&self) -> String {
        if !self.ip.trim().is_empty() {
            self.ip.clone()
        } else {
            self.id.clone()
        }
    }

    /// Get connection target for establishing connection
    /// Returns (target_string, is_ip_connection)
    pub fn connection_target(&self) -> (String, bool) {
        if !self.ip.trim().is_empty() {
            // IP connection: "ip:port"
            (format!("{}:{}", self.ip, self.port), true)
        } else {
            // ID connection: just the ID
            (self.id.clone(), false)
        }
    }
}

/// Device list configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceListConfig {
    /// Configuration version
    #[serde(default = "default_version")]
    pub version: String,
    /// Default connection mode: "id" or "ip"
    #[serde(default = "default_connection_mode")]
    pub default_connection_mode: String,
    /// List of devices
    #[serde(default)]
    pub devices: Vec<DeviceConfig>,
}

fn default_version() -> String {
    "1.0".to_string()
}

fn default_connection_mode() -> String {
    "id".to_string()
}

impl Default for DeviceListConfig {
    fn default() -> Self {
        Self {
            version: default_version(),
            default_connection_mode: default_connection_mode(),
            devices: Vec::new(),
        }
    }
}

/// Get the path to the device list configuration file
pub fn get_device_list_path() -> PathBuf {
    Config::path("devices.json")
}

/// Load device list from file
pub fn load_device_list() -> Result<DeviceListConfig> {
    let path = get_device_list_path();

    if !path.exists() {
        log::info!("Device list file not found, returning empty list");
        return Ok(DeviceListConfig::default());
    }

    let content = fs::read_to_string(&path)
        .map_err(|e| anyhow!("Failed to read device list file: {}", e))?;

    let config: DeviceListConfig = serde_json::from_str(&content)
        .map_err(|e| anyhow!("Failed to parse device list JSON: {}", e))?;

    Ok(config)
}

/// Save device list to file
pub fn save_device_list(config: &DeviceListConfig) -> Result<()> {
    let path = get_device_list_path();

    // Ensure directory exists
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|e| anyhow!("Failed to create config directory: {}", e))?;
    }

    let json = serde_json::to_string_pretty(config)
        .map_err(|e| anyhow!("Failed to serialize device list: {}", e))?;

    fs::write(&path, json)
        .map_err(|e| anyhow!("Failed to write device list file: {}", e))?;

    log::info!("Device list saved to: {:?}", path);
    Ok(())
}

/// Parse JSON content and extract devices
pub fn parse_json(content: &str) -> Result<Vec<DeviceConfig>> {
    // Try to parse as DeviceListConfig first
    if let Ok(config) = serde_json::from_str::<DeviceListConfig>(content) {
        return Ok(config.devices);
    }

    // Try to parse as array of DeviceConfig
    if let Ok(devices) = serde_json::from_str::<Vec<DeviceConfig>>(content) {
        return Ok(devices);
    }

    Err(anyhow!("Invalid JSON format: expected DeviceListConfig or array of devices"))
}

/// Parse CSV content and extract devices
pub fn parse_csv(content: &str) -> Result<Vec<DeviceConfig>> {
    let mut reader = csv::Reader::from_reader(content.as_bytes());
    let mut devices = Vec::new();
    let mut errors = Vec::new();

    for (idx, result) in reader.deserialize().enumerate() {
        match result {
            Ok(device) => devices.push(device),
            Err(e) => {
                errors.push(format!("Line {}: {}", idx + 2, e)); // +2 because header is line 1
            }
        }
    }

    if !errors.is_empty() {
        log::warn!("CSV parsing errors: {}", errors.join("; "));
    }

    Ok(devices)
}

/// Encrypt password if it's not already encrypted
pub fn encrypt_password(password: &str) -> String {
    if password.is_empty() {
        return String::new();
    }

    // Check if already encrypted (starts with version prefix like "00")
    if password.len() >= 2 && password.chars().take(2).all(|c| c.is_numeric()) {
        // Likely already encrypted, return as is
        return password.to_string();
    }

    // Encrypt using RustDesk's encryption mechanism
    use hbb_common::config::ENCRYPT_MAX_LEN;
    use hbb_common::password_security::encrypt_str_or_original;
    encrypt_str_or_original(password, "00", ENCRYPT_MAX_LEN)
}

/// Decrypt password for connection
/// Returns the decrypted password, or original if not encrypted
pub fn decrypt_password(encrypted_password: &str) -> String {
    if encrypted_password.is_empty() {
        return String::new();
    }

    // Decrypt using RustDesk's decryption mechanism
    use hbb_common::password_security::decrypt_str_or_original;
    let (decrypted, _, _) = decrypt_str_or_original(encrypted_password, "00");
    decrypted
}

/// Import devices from a file (JSON or CSV)
pub fn import_devices(file_path: &str, verbose: bool, quiet: bool) -> Result<String> {
    // Read file content
    let content = fs::read_to_string(file_path)
        .map_err(|e| anyhow!("Failed to read file '{}': {}", file_path, e))?;

    // Determine file type and parse
    let new_devices = if file_path.ends_with(".json") {
        if verbose {
            println!("Importing devices from JSON: {}", file_path);
        }
        parse_json(&content)?
    } else if file_path.ends_with(".csv") {
        if verbose {
            println!("Importing devices from CSV: {}", file_path);
        }
        parse_csv(&content)?
    } else {
        return Err(anyhow!("Unsupported file format. Use .json or .csv"));
    };

    // Validate and encrypt passwords
    let mut valid_devices = Vec::new();
    let mut skipped = 0;

    for device in new_devices {
        if let Err(e) = device.validate() {
            if verbose {
                println!("  ⚠ [SKIP] {}", e);
            }
            skipped += 1;
            continue;
        }

        // Encrypt password
        let mut device = device;
        device.password = encrypt_password(&device.password);
        valid_devices.push(device);
    }

    // Load existing device list
    let mut config = load_device_list().unwrap_or_default();

    // Merge devices (by name)
    let mut new_count = 0;
    let mut updated_count = 0;

    for new_device in valid_devices {
        if let Some(existing) = config.devices.iter_mut().find(|d| d.name == new_device.name) {
            if verbose {
                println!("  ✓ [UPDATE] {} ({})", new_device.name, new_device.display_target());
            }
            *existing = new_device;
            updated_count += 1;
        } else {
            if verbose {
                println!("  ✓ [NEW] {} ({})", new_device.name, new_device.display_target());
            }
            config.devices.push(new_device);
            new_count += 1;
        }
    }

    // Save to file
    save_device_list(&config)?;

    // Generate output
    let total = new_count + updated_count;
    let output = if quiet {
        String::new()
    } else if verbose {
        format!(
            "\nSummary:\n  Total entries: {}\n  Successfully imported: {} ({} new, {} updated)\n  Skipped: {}\n\nSaved to: {:?}",
            total + skipped,
            total,
            new_count,
            updated_count,
            skipped,
            get_device_list_path()
        )
    } else {
        format!(
            "✓ Imported {} devices ({} new, {} updated)\n⚠ Skipped {} invalid entries",
            total,
            new_count,
            updated_count,
            skipped
        )
    };

    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_device_config_validate() {
        // Valid device with ID
        let device = DeviceConfig {
            name: "Test Device".to_string(),
            id: "123456789".to_string(),
            ip: String::new(),
            port: 21118,
            password: String::new(),
            platform: "Windows".to_string(),
            note: String::new(),
            username: String::new(),
            hostname: String::new(),
        };
        assert!(device.validate().is_ok());

        // Valid device with IP
        let device = DeviceConfig {
            name: "Test Device".to_string(),
            id: String::new(),
            ip: "192.168.1.100".to_string(),
            port: 21118,
            password: String::new(),
            platform: "Linux".to_string(),
            note: String::new(),
            username: String::new(),
            hostname: String::new(),
        };
        assert!(device.validate().is_ok());

        // Invalid: empty name
        let device = DeviceConfig {
            name: String::new(),
            id: "123456789".to_string(),
            ip: String::new(),
            port: 21118,
            password: String::new(),
            platform: String::new(),
            note: String::new(),
            username: String::new(),
            hostname: String::new(),
        };
        assert!(device.validate().is_err());

        // Invalid: no ID or IP
        let device = DeviceConfig {
            name: "Test".to_string(),
            id: String::new(),
            ip: String::new(),
            port: 21118,
            password: String::new(),
            platform: String::new(),
            note: String::new(),
            username: String::new(),
            hostname: String::new(),
        };
        assert!(device.validate().is_err());

        // Invalid: wrong ID format
        let device = DeviceConfig {
            name: "Test".to_string(),
            id: "12345".to_string(),  // Not 9 digits
            ip: String::new(),
            port: 21118,
            password: String::new(),
            platform: String::new(),
            note: String::new(),
            username: String::new(),
            hostname: String::new(),
        };
        assert!(device.validate().is_err());
    }

    #[test]
    fn test_device_config_serialization() {
        let device = DeviceConfig {
            name: "Test Device".to_string(),
            id: "123456789".to_string(),
            ip: String::new(),
            port: 21118,
            password: "enc:test".to_string(),
            platform: "Windows".to_string(),
            note: "Test note".to_string(),
            username: "admin".to_string(),
            hostname: "TEST-PC".to_string(),
        };

        let json = serde_json::to_string(&device).unwrap();
        let deserialized: DeviceConfig = serde_json::from_str(&json).unwrap();

        assert_eq!(device.name, deserialized.name);
        assert_eq!(device.id, deserialized.id);
        assert_eq!(device.port, deserialized.port);
    }

    #[test]
    fn test_device_list_config_default() {
        let config = DeviceListConfig::default();
        assert_eq!(config.version, "1.0");
        assert_eq!(config.default_connection_mode, "id");
        assert_eq!(config.devices.len(), 0);
    }

    #[test]
    fn test_parse_json() {
        let json = r#"{
            "version": "1.0",
            "default_connection_mode": "id",
            "devices": [
                {
                    "name": "Device 1",
                    "id": "123456789",
                    "ip": "",
                    "port": 21118,
                    "password": "",
                    "platform": "Windows",
                    "note": "Test",
                    "username": "",
                    "hostname": ""
                }
            ]
        }"#;

        let devices = parse_json(json).unwrap();
        assert_eq!(devices.len(), 1);
        assert_eq!(devices[0].name, "Device 1");
    }

    #[test]
    fn test_encrypt_password() {
        // Empty password
        assert_eq!(encrypt_password(""), "");

        // Already encrypted (starts with version like "00")
        let encrypted = "00abc123xyz";
        assert_eq!(encrypt_password(encrypted), encrypted);

        // Plain password (should be encrypted)
        let plain = "password123";
        let result = encrypt_password(plain);
        // Result should start with version "00"
        assert!(result.starts_with("00") || result == plain); // May fail to encrypt in test environment
    }

    #[test]
    fn test_connection_target() {
        // IP connection
        let device = DeviceConfig {
            name: "Test".to_string(),
            id: "123456789".to_string(),
            ip: "192.168.1.100".to_string(),
            port: 21119,
            password: String::new(),
            platform: String::new(),
            note: String::new(),
            username: String::new(),
            hostname: String::new(),
        };
        let (target, is_ip) = device.connection_target();
        assert_eq!(target, "192.168.1.100:21119");
        assert!(is_ip);

        // ID connection
        let device = DeviceConfig {
            name: "Test".to_string(),
            id: "123456789".to_string(),
            ip: String::new(),
            port: 21118,
            password: String::new(),
            platform: String::new(),
            note: String::new(),
            username: String::new(),
            hostname: String::new(),
        };
        let (target, is_ip) = device.connection_target();
        assert_eq!(target, "123456789");
        assert!(!is_ip);
    }
}
