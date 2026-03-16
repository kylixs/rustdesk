// Phase 5: Signature Generator for licence_key
// This module generates signed licence_key with format: version:timestamp:signature

use sha2::{Sha256, Digest};
use std::time::{SystemTime, UNIX_EPOCH};

/// Version for the custom client
const VERSION: &str = "custom-1.0";

/// Secret key for signature generation (should be same as server)
const SECRET_KEY: &str = "rustdesk-custom-secret-key-2026";

/// Generate a new signed licence_key
/// Format: version:timestamp:signature
pub fn generate_signed_licence_key() -> String {
    let timestamp = get_current_timestamp();
    let signature = generate_signature(VERSION, timestamp);
    format!("{}:{}:{}", VERSION, timestamp, signature)
}

/// Get current timestamp in seconds
fn get_current_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
}

/// Generate SHA256 signature
/// Signature = SHA256(version + timestamp + secret_key)
fn generate_signature(version: &str, timestamp: u64) -> String {
    let mut hasher = Sha256::new();
    let data = format!("{}{}{}", version, timestamp, SECRET_KEY);
    hasher.update(data.as_bytes());
    let result = hasher.finalize();
    hex::encode(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_signed_licence_key() {
        let key = generate_signed_licence_key();
        let parts: Vec<&str> = key.split(':').collect();
        assert_eq!(parts.len(), 3);
        assert_eq!(parts[0], VERSION);
        assert!(parts[1].parse::<u64>().is_ok());
        assert_eq!(parts[2].len(), 64); // SHA256 hex length
    }

    #[test]
    fn test_signature_generation() {
        let timestamp = 1234567890;
        let signature = generate_signature(VERSION, timestamp);
        assert_eq!(signature.len(), 64);
        
        // Same inputs should produce same signature
        let signature2 = generate_signature(VERSION, timestamp);
        assert_eq!(signature, signature2);
    }
}
