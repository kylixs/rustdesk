// Phase 3: 版本验证模块
use hbb_common::log;
// 防止标准版Rustdesk绕过Phase 2的安全机制

use sha2::{Digest, Sha256};
use std::time::{SystemTime, UNIX_EPOCH};

/// 版本验证器
pub struct VersionValidator {
    /// 允许的版本列表
    allowed_versions: Vec<String>,
    /// 密钥（用于签名验证）
    secret_key: String,
    /// 时间戳容忍度（秒），防止重放攻击
    timestamp_tolerance: u64,
}

impl VersionValidator {
    /// 创建新的版本验证器
    pub fn new(secret_key: String) -> Self {
        Self {
            allowed_versions: vec!["custom-1.0".to_string()],
            secret_key,
            timestamp_tolerance: 300, // 5分钟容忍度
        }
    }

    /// 添加允许的版本
    pub fn add_allowed_version(&mut self, version: String) {
        if !self.allowed_versions.contains(&version) {
            self.allowed_versions.push(version);
        }
    }

    /// 验证版本和签名
    /// 
    /// # 参数
    /// - version: 版本字符串（如"custom-1.0"）
    /// - timestamp: 时间戳（Unix时间戳）
    /// - signature: 签名（SHA256(version + timestamp + secret_key)）
    /// 
    /// # 返回
    /// - true: 验证成功
    /// - false: 验证失败
    pub fn verify(&self, version: &str, timestamp: u64, signature: &str) -> bool {
        // 1. 检查版本是否在允许列表中
        if !self.allowed_versions.contains(&version.to_string()) {
            log::warn!("Version not allowed: {}", version);
            return false;
        }

        // 2. 检查时间戳（防止重放攻击）
        let current_time = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
        
        if timestamp > current_time + self.timestamp_tolerance {
            log::warn!("Timestamp is in the future: {} > {}", timestamp, current_time);
            return false;
        }
        
        if current_time > timestamp + self.timestamp_tolerance {
            log::warn!("Timestamp is too old: {} < {}", timestamp, current_time);
            return false;
        }

        // 3. 验证签名
        let expected_signature = self.generate_signature(version, timestamp);
        if expected_signature != signature {
            log::warn!("Signature verification failed: expected {}, got {}", expected_signature, signature);
            return false;
        }

        log::info!("Version verification succeeded: {}", version);
        true
    }

    /// 生成签名
    /// 
    /// # 参数
    /// - version: 版本字符串
    /// - timestamp: 时间戳
    /// 
    /// # 返回
    /// - 签名字符串（十六进制）
    pub fn generate_signature(&self, version: &str, timestamp: u64) -> String {
        let data = format!("{}{}{}", version, timestamp, self.secret_key);
        let mut hasher = Sha256::new();
        hasher.update(data.as_bytes());
        let result = hasher.finalize();
        hex::encode(result)
    }

    /// 从licence_key解析版本信息
    /// 
    /// licence_key格式：version:timestamp:signature
    /// 例如：custom-1.0:1234567890:abc123...
    /// 
    /// # 参数
    /// - licence_key: 许可证密钥
    /// 
    /// # 返回
    /// - Some((version, timestamp, signature)): 解析成功
    /// - None: 解析失败
    pub fn parse_licence_key(licence_key: &str) -> Option<(String, u64, String)> {
        let parts: Vec<&str> = licence_key.split(':').collect();
        if parts.len() != 3 {
            log::warn!("Invalid licence_key format: {}", licence_key);
            return None;
        }

        let version = parts[0].to_string();
        let timestamp = parts[1].parse::<u64>().ok()?;
        let signature = parts[2].to_string();

        Some((version, timestamp, signature))
    }

    /// 验证licence_key
    /// 
    /// # 参数
    /// - licence_key: 许可证密钥（格式：version:timestamp:signature）
    /// 
    /// # 返回
    /// - true: 验证成功
    /// - false: 验证失败
    pub fn verify_licence_key(&self, licence_key: &str) -> bool {
        if let Some((version, timestamp, signature)) = Self::parse_licence_key(licence_key) {
            self.verify(&version, timestamp, &signature)
        } else {
            false
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_version_validator() {
        let validator = VersionValidator::new("test_secret_key".to_string());
        
        let version = "custom-1.0";
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
        let signature = validator.generate_signature(version, timestamp);
        
        // 验证应该成功
        assert!(validator.verify(version, timestamp, &signature));
        
        // 错误的版本应该失败
        assert!(!validator.verify("wrong-version", timestamp, &signature));
        
        // 错误的签名应该失败
        assert!(!validator.verify(version, timestamp, "wrong_signature"));
    }

    #[test]
    fn test_licence_key_parsing() {
        let licence_key = "custom-1.0:1234567890:abc123";
        let result = VersionValidator::parse_licence_key(licence_key);
        
        assert!(result.is_some());
        let (version, timestamp, signature) = result.unwrap();
        assert_eq!(version, "custom-1.0");
        assert_eq!(timestamp, 1234567890);
        assert_eq!(signature, "abc123");
    }
}
