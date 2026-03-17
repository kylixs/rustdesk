// Phase 5: Signature Generator for licence_key (Configuration Support)
// This module generates signed licence_key with format: version:timestamp:signature

use sha2::{Sha256, Digest};
use std::time::{SystemTime, UNIX_EPOCH};
use std::env;

/// Get secret key from environment variable or use default
/// Production environment should set RUSTDESK_SECRET_KEY
fn get_secret_key() -> String {
    match env::var("RUSTDESK_SECRET_KEY") {
        Ok(key) => key,
        Err(_) => {
            // Default key for development only
            // WARNING: Do not use in production!
            #[cfg(debug_assertions)]
            eprintln!("WARNING: Using default secret key. Set RUSTDESK_SECRET_KEY for production!");
            "rustdesk-custom-secret-key-2026".to_string()
        }
    }
}

/// Get version from environment variable or use default
fn get_version() -> String {
    match env::var("RUSTDESK_CUSTOM_VERSION") {
        Ok(version) => version,
        Err(_) => "custom-1.0".to_string()
    }
}

/// Generate a new signed licence_key
/// Format: version:timestamp:signature
pub fn generate_signed_licence_key() -> String {
    let version = get_version();
    let timestamp = get_current_timestamp();
    let secret_key = get_secret_key();
    let signature = generate_signature(&version, timestamp, &secret_key);
    
    format!("{}:{}:{}", version, timestamp, signature)
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
fn generate_signature(version: &str, timestamp: u64, secret_key: &str) -> String {
    let mut hasher = Sha256::new();
    let data = format!("{}{}{}", version, timestamp, secret_key);
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
        assert!(parts[1].parse::<u64>().is_ok());
        assert_eq!(parts[2].len(), 64); // SHA256 hex length
    }

    #[test]
    fn test_signature_generation() {
        let version = "custom-1.0";
        let timestamp = 1234567890;
        let secret_key = "test-secret";
        let signature = generate_signature(version, timestamp, secret_key);
        assert_eq!(signature.len(), 64);
        
        // Same inputs should produce same signature
        let signature2 = generate_signature(version, timestamp, secret_key);
        assert_eq!(signature, signature2);
    }

    #[test]
    fn test_environment_variable() {
        // Test with custom environment variable
        env::set_var("RUSTDESK_SECRET_KEY", "test-env-key");
        let key = get_secret_key();
        assert_eq!(key, "test-env-key");
        env::remove_var("RUSTDESK_SECRET_KEY");
        
        // Test with default
        let default_key = get_secret_key();
        assert_eq!(default_key, "rustdesk-custom-secret-key-2026");
    }
}
