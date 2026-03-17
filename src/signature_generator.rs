// Phase 5: Signature Generator for licence_key (Performance Optimized)
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
            String::from("rustdesk-custom-secret-key-2026")
        }
    }
}

/// Get version from environment variable or use default
fn get_version() -> String {
    match env::var("RUSTDESK_CUSTOM_VERSION") {
        Ok(version) => version,
        Err(_) => String::from("custom-1.0")
    }
}

/// Generate a new signed licence_key
/// Format: version:timestamp:signature
/// Performance optimized: uses String::with_capacity to avoid reallocations
pub fn generate_signed_licence_key() -> String {
    let version = get_version();
    let timestamp = get_current_timestamp();
    let secret_key = get_secret_key();
    let signature = generate_signature(&version, timestamp, &secret_key);
    
    // Performance optimization: pre-allocate string capacity
    // version(10) + ":" + timestamp(10) + ":" + signature(64) = ~85 chars
    let mut result = String::with_capacity(90);
    result.push_str(&version);
    result.push(':');
    result.push_str(&timestamp.to_string());
    result.push(':');
    result.push_str(&signature);
    
    result
}

/// Get current timestamp in seconds
/// Performance optimized: avoids unwrap() by using unwrap_or_default()
fn get_current_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

/// Generate SHA256 signature
/// Signature = SHA256(version + timestamp + secret_key)
/// Performance optimized: uses String::with_capacity
fn generate_signature(version: &str, timestamp: u64, secret_key: &str) -> String {
    let mut hasher = Sha256::new();
    
    // Performance optimization: pre-allocate string capacity
    // version(10) + timestamp(10) + secret_key(40) = ~60 chars
    let mut data = String::with_capacity(70);
    data.push_str(version);
    data.push_str(&timestamp.to_string());
    data.push_str(secret_key);
    
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

    #[test]
    fn test_performance() {
        use std::time::Instant;
        
        // Test generation performance
        let start = Instant::now();
        for _ in 0..1000 {
            let _ = generate_signed_licence_key();
        }
        let duration = start.elapsed();
        
        // Should generate 1000 keys in less than 100ms
        assert!(duration.as_millis() < 100, "Performance test failed: {:?}", duration);
        
        println!("Generated 1000 licence_keys in {:?}", duration);
    }
}
