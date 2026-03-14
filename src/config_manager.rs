// Config Manager for Phase 2 - Bastion Mode
// 配置管理模块：堡垒机模式与复制策略

use serde::{Deserialize, Serialize};
use hbb_common::log;
use std::fs;
use std::io::Read;
use std::net::IpAddr;
use std::path::Path;
use std::sync::{Arc, RwLock};
use std::time::UNIX_EPOCH;

/// 复制策略枚举
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum CopyStrategy {
    #[serde(rename = "no_copy")]
    NoCopy,              // 完全禁止复制
    #[serde(rename = "client_to_server")]
    ClientToServer,      // 只允许客户端→服务端（默认）
    #[serde(rename = "server_to_client")]
    ServerToClient,      // 只允许服务端→客户端
    #[serde(rename = "bidirectional")]
    Bidirectional,       // 允许双向复制
    #[serde(rename = "reject")]
    Reject,              // 拒绝连接
}

/// 服务器条目
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerEntry {
    pub ip: String,
    pub strategy: CopyStrategy,
    pub description: String,
    #[serde(default = "default_enabled")]
    pub enabled: bool,
}

fn default_enabled() -> bool {
    true
}

/// 服务器配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    pub version: String,
    pub server_whitelist: Vec<ServerEntry>,
    #[serde(rename = "defaultStrategy", default = "default_strategy")]
    pub default_strategy: CopyStrategy,
    #[serde(rename = "hotReload", default = "default_hot_reload")]
    pub hot_reload: bool,
    #[serde(rename = "configCheckInterval", default = "default_check_interval")]
    pub config_check_interval: u64,
}

fn default_strategy() -> CopyStrategy {
    CopyStrategy::Reject
}

fn default_hot_reload() -> bool {
    true
}

fn default_check_interval() -> u64 {
    30
}

impl Default for ServerConfig {
    fn default() -> Self {
        ServerConfig {
            version: "1.0".to_string(),
            server_whitelist: vec![],
            default_strategy: CopyStrategy::Reject,
            hot_reload: true,
            config_check_interval: 30,
        }
    }
}

/// 配置管理器
pub struct ConfigManager {
    config: Arc<RwLock<ServerConfig>>,
    config_path: String,
    last_modified: u64,
}

impl ConfigManager {
    pub fn new(config_path: &str) -> Self {
        ConfigManager {
            config: Arc::new(RwLock::new(ServerConfig::default())),
            config_path: config_path.to_string(),
            last_modified: 0,
        }
    }

    pub fn load_config(&mut self) -> Result<(), String> {
        let path = Path::new(&self.config_path);

        if !path.exists() {
            self.create_default_config()?;
            return Ok(());
        }

        let mut file = fs::File::open(path)
            .map_err(|e| format!("无法打开配置文件: {}", e))?;

        let mut contents = String::new();
        file.read_to_string(&mut contents)
            .map_err(|e| format!("读取配置文件失败: {}", e))?;

        let config: ServerConfig = serde_json::from_str(&contents)
            .map_err(|e| format!("解析配置文件失败: {}", e))?;

        self.validate_config(&config)?;

        let mut current_config = self.config.write().unwrap();
        *current_config = config;

        if let Ok(metadata) = fs::metadata(path) {
            if let Ok(modified) = metadata.modified() {
                self.last_modified = modified
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_secs();
            }
        }

        log::info!("配置文件加载成功: {}", self.config_path);
        Ok(())
    }

    fn create_default_config(&self) -> Result<(), String> {
        let default_config = ServerConfig::default();
        let json = serde_json::to_string_pretty(&default_config)
            .map_err(|e| format!("序列化默认配置失败: {}", e))?;

        fs::write(&self.config_path, json)
            .map_err(|e| format!("写入默认配置失败: {}", e))?;

        log::info!("创建默认配置文件: {}", self.config_path);
        Ok(())
    }

    fn validate_config(&self, config: &ServerConfig) -> Result<(), String> {
        if config.version.is_empty() {
            return Err("配置版本不能为空".to_string());
        }

        for entry in &config.server_whitelist {
            if !self.is_valid_ip_or_cidr(&entry.ip) {
                return Err(format!("无效的IP地址或CIDR: {}", entry.ip));
            }

            if entry.description.is_empty() {
                return Err(format!("服务器描述不能为空: {}", entry.ip));
            }
        }

        Ok(())
    }

    fn is_valid_ip_or_cidr(&self, ip_str: &str) -> bool {
        if ip_str.parse::<IpAddr>().is_ok() {
            return true;
        }

        if ip_str.contains('/') {
            let parts: Vec<&str> = ip_str.split('/').collect();
            if parts.len() == 2 {
                if let Ok(_ip) = parts[0].parse::<IpAddr>() {
                    if let Ok(prefix) = parts[1].parse::<u8>() {
                        match parts[0].parse::<IpAddr>() {
                            Ok(IpAddr::V4(_)) => return prefix <= 32,
                            Ok(IpAddr::V6(_)) => return prefix <= 128,
                            _ => {}
                        }
                    }
                }
            }
        }

        false
    }

    pub fn reload_if_modified(&mut self) -> Result<bool, String> {
        let path = Path::new(&self.config_path);

        if !path.exists() {
            return Ok(false);
        }

        if let Ok(metadata) = fs::metadata(path) {
            if let Ok(modified) = metadata.modified() {
                let modified_secs = modified
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_secs();

                if modified_secs > self.last_modified {
                    log::info!("检测到配置文件修改，重新加载...");
                    self.load_config()?;
                    return Ok(true);
                }
            }
        }

        Ok(false)
    }

    pub fn get_config(&self) -> Arc<RwLock<ServerConfig>> {
        Arc::clone(&self.config)
    }

    pub fn get_strategy_for_ip(&self, ip: &IpAddr) -> CopyStrategy {
        let config = self.config.read().unwrap();

        for entry in &config.server_whitelist {
            if !entry.enabled {
                continue;
            }

            if self.ip_matches_pattern(ip, &entry.ip) {
                return entry.strategy.clone();
            }
        }

        config.default_strategy.clone()
    }

    fn ip_matches_pattern(&self, ip: &IpAddr, pattern: &str) -> bool {
        if let Ok(pattern_ip) = pattern.parse::<IpAddr>() {
            return ip == &pattern_ip;
        }

        if pattern.contains('/') {
            let parts: Vec<&str> = pattern.split('/').collect();
            if parts.len() == 2 {
                if let Ok(network_ip) = parts[0].parse::<IpAddr>() {
                    if let Ok(prefix_len) = parts[1].parse::<u8>() {
                        return self.ip_in_cidr(ip, &network_ip, prefix_len);
                    }
                }
            }
        }

        false
    }

    fn ip_in_cidr(&self, ip: &IpAddr, network: &IpAddr, prefix_len: u8) -> bool {
        match (ip, network) {
            (IpAddr::V4(ip_v4), IpAddr::V4(network_v4)) => {
                if prefix_len > 32 {
                    return false;
                }
                let mask = if prefix_len == 0 {
                    0
                } else {
                    !0u32 << (32 - prefix_len)
                };
                let ip_bits = u32::from(*ip_v4);
                let network_bits = u32::from(*network_v4);
                (ip_bits & mask) == (network_bits & mask)
            }
            (IpAddr::V6(ip_v6), IpAddr::V6(network_v6)) => {
                if prefix_len > 128 {
                    return false;
                }
                let mask = if prefix_len == 0 {
                    0
                } else {
                    !0u128 << (128 - prefix_len)
                };
                let ip_bits = u128::from(*ip_v6);
                let network_bits = u128::from(*network_v6);
                (ip_bits & mask) == (network_bits & mask)
            }
            _ => false,
        }
    }
}
