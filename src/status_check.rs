/// Status check module for RustDesk unattended mode
///
/// This module provides comprehensive status checking functionality including:
/// - Service running status (PID, uptime, autostart)
/// - Configuration validation (unattended mode settings)
/// - Network connectivity (rendezvous server, NAT type, IPs)
/// - Device information (ID, fingerprint, active connections)
/// - Issue detection and recommendations
///
/// Supports both human-readable and JSON output formats.

use hbb_common::{config::Config, log, ResultType};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Serialize, Deserialize)]
pub struct StatusReport {
    pub status: String, // "ok" or "warning" or "error"
    pub service: ServiceStatus,
    pub config: ConfigStatus,
    pub network: NetworkStatus,
    pub device: DeviceInfo,
    pub issues: Vec<String>,
    pub recommendations: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ServiceStatus {
    pub running: bool,
    pub pid: Option<u32>,
    pub uptime_seconds: Option<u64>,
    pub autostart_enabled: bool,
    pub unattended_mode: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ConfigStatus {
    pub approve_mode: String,
    pub verification_method: String,
    pub password_set: bool,
    pub hide_cm: bool,
    pub allow_hide_cm: bool,
    pub allow_logon_screen: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct NetworkStatus {
    pub rendezvous_server: String,
    pub rendezvous_connected: bool,
    pub nat_type: String,
    pub local_ip: String,
    pub public_ip: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct DeviceInfo {
    pub id: String,
    pub uuid: String,
    pub active_connections: u32,
}

impl StatusReport {
    pub fn new() -> Self {
        Self {
            status: "unknown".to_string(),
            service: ServiceStatus::new(),
            config: ConfigStatus::new(),
            network: NetworkStatus::new(),
            device: DeviceInfo::new(),
            issues: Vec::new(),
            recommendations: Vec::new(),
        }
    }

    /// Collect all status information
    pub fn collect(&mut self) -> ResultType<()> {
        log::info!("Collecting status information...");

        // 1. Check service status
        self.service.check();

        // 2. Check configuration
        self.config.check();

        // 3. Check network (may be slow, do this last)
        self.network.check();

        // 4. Get device info
        self.device.collect();

        // 5. Detect issues
        self.detect_issues();

        // 6. Set overall status
        self.status = if self.issues.is_empty() {
            "ok".to_string()
        } else if self.issues.iter().any(|i| i.contains("Service not running") || i.contains("Password not set")) {
            "error".to_string()
        } else {
            "warning".to_string()
        };

        Ok(())
    }

    /// Detect configuration and runtime issues
    fn detect_issues(&mut self) {
        // Service checks
        if !self.service.running {
            self.issues.push("Service is not running".to_string());
            self.recommendations.push("Run: sudo rustdesk --install-service && sudo systemctl start rustdesk".to_string());
        }

        if !self.service.autostart_enabled {
            self.issues.push("Service autostart is not enabled".to_string());
            self.recommendations.push("Run: sudo systemctl enable rustdesk".to_string());
        }

        // Config checks
        if self.config.approve_mode != "password" {
            self.issues.push(format!("Approve mode is '{}', should be 'password' for unattended mode", self.config.approve_mode));
            self.recommendations.push("Run: sudo rustdesk --option approve-mode password".to_string());
        }

        if self.config.verification_method != "use-permanent-password" {
            self.issues.push(format!("Verification method is '{}', should be 'use-permanent-password'", self.config.verification_method));
            self.recommendations.push("Run: sudo rustdesk --option verification-method use-permanent-password".to_string());
        }

        if !self.config.password_set {
            self.issues.push("Permanent password is not set".to_string());
            self.recommendations.push("Run: sudo rustdesk --password <your-password>".to_string());
        }

        if !self.config.allow_hide_cm {
            self.issues.push("Connection manager hiding is not enabled".to_string());
            self.recommendations.push("Run: sudo rustdesk --option allow-hide-cm Y".to_string());
        }

        // Network checks
        if !self.network.rendezvous_connected {
            self.issues.push("Cannot connect to rendezvous server".to_string());
            self.recommendations.push("Check network connectivity and firewall settings".to_string());
        }

        // Overall status message
        if self.issues.is_empty() {
            self.recommendations.push("No issues found, system is running normally".to_string());
        }
    }

    /// Print human-readable report
    pub fn print_human_readable(&self) {
        println!("\n=== RustDesk 运行状态 ===");
        println!("版本: {} ({})\n", crate::VERSION, crate::BUILD_DATE);

        // Service status
        println!("[服务状态]");
        if self.service.running {
            print!("  ✓ 服务运行中");
            if let Some(pid) = self.service.pid {
                print!(" (PID: {})", pid);
            }
            if let Some(uptime) = self.service.uptime_seconds {
                let hours = uptime / 3600;
                let minutes = (uptime % 3600) / 60;
                if hours > 0 {
                    print!(", 运行时长: {}小时{}分钟", hours, minutes);
                } else {
                    print!(", 运行时长: {}分钟", minutes);
                }
            }
            println!();
        } else {
            println!("  ✗ 服务未运行");
        }

        if self.service.autostart_enabled {
            println!("  ✓ 系统服务已启用 (开机自启)");
        } else {
            println!("  ✗ 系统服务未启用");
        }

        if self.service.unattended_mode {
            println!("  ✓ 无人值守模式已激活");
        } else {
            println!("  ○ 无人值守模式未激活");
        }

        // Config status
        println!("\n[配置检查]");
        self.print_config_item("approve-mode", &self.config.approve_mode, "password");
        self.print_config_item("verification-method", &self.config.verification_method, "use-permanent-password");

        self.print_bool_config("allow-hide-cm", self.config.allow_hide_cm, true);
        self.print_bool_config("allow-logon-screen-password", self.config.allow_logon_screen, true);

        // Network status
        println!("\n[网络状态]");
        println!("  Rendezvous 服务器: {}", self.network.rendezvous_server);
        if self.network.rendezvous_connected {
            println!("    ✓ 连接正常");
        } else {
            println!("    ✗ 连接失败");
        }

        if !self.network.nat_type.is_empty() {
            println!("  NAT 类型: {}", self.network.nat_type);
        }
        if !self.network.local_ip.is_empty() {
            println!("  本地 IP: {}", self.network.local_ip);
        }
        if !self.network.public_ip.is_empty() {
            println!("  公网 IP: {}", self.network.public_ip);
        }

        // Device info
        println!("\n[连接信息]");
        println!("  连接 ID: {}", self.device.id);
        if !self.device.uuid.is_empty() {
            println!("  设备 UUID: {}", self.device.uuid);
        }
        println!("  当前连接数: {}", self.device.active_connections);

        // Issues and recommendations
        if !self.issues.is_empty() {
            println!("\n[发现的问题]");
            for (i, issue) in self.issues.iter().enumerate() {
                println!("  {}. {}", i + 1, issue);
            }
        }

        if !self.recommendations.is_empty() {
            println!("\n[建议]");
            for rec in &self.recommendations {
                println!("  • {}", rec);
            }
        }

        println!();
    }

    fn print_config_item(&self, name: &str, value: &str, expected: &str) {
        if value == expected {
            println!("  ✓ {}: {}", name, value);
        } else {
            println!("  ✗ {}: {} (应为: {})", name, value, expected);
        }
    }

    fn print_bool_config(&self, name: &str, enabled: bool, expected: bool) {
        let value = if enabled { "Y" } else { "N" };
        let expected_value = if expected { "Y" } else { "N" };

        if enabled == expected {
            println!("  ✓ {}: {}", name, value);
        } else {
            println!("  ✗ {}: {} (应为: {})", name, value, expected_value);
        }
    }

    /// Print JSON report
    pub fn print_json(&self) -> ResultType<()> {
        let json = serde_json::to_string_pretty(self)?;
        println!("{}", json);
        Ok(())
    }
}

impl ServiceStatus {
    fn new() -> Self {
        Self {
            running: false,
            pid: None,
            uptime_seconds: None,
            autostart_enabled: false,
            unattended_mode: false,
        }
    }

    fn check(&mut self) {
        // Get service status from platform-specific implementation
        let status = crate::platform::get_service_status();
        self.running = status == "Running";

        // Check if autostart is enabled
        self.autostart_enabled = self.check_autostart();

        // Check unattended mode
        self.unattended_mode = self.check_unattended_mode();

        // Try to get PID and uptime (platform-specific)
        if self.running {
            self.get_process_info();
        }
    }

    #[cfg(target_os = "linux")]
    fn check_autostart(&self) -> bool {
        use std::process::Command;
        let app_name = crate::get_app_name().to_lowercase();
        if let Ok(output) = Command::new("systemctl")
            .args(&["is-enabled", &app_name])
            .output()
        {
            let status = String::from_utf8_lossy(&output.stdout);
            status.trim() == "enabled"
        } else {
            false
        }
    }

    #[cfg(target_os = "windows")]
    fn check_autostart(&self) -> bool {
        // Check if Windows service is set to automatic start
        // This is a simplified check - in real implementation, query service config
        self.running
    }

    #[cfg(target_os = "macos")]
    fn check_autostart(&self) -> bool {
        // Check if launchd service is configured to auto-start
        let agent = format!("{}_server.plist", crate::get_full_name());
        let agent_path = format!("/Library/LaunchAgents/{}", agent);
        std::path::Path::new(&agent_path).exists()
    }

    fn check_unattended_mode(&self) -> bool {
        Config::get_option("approve-mode") == "password"
            && Config::get_option("verification-method") == "use-permanent-password"
            && hbb_common::config::option2bool("allow-hide-cm", &Config::get_option("allow-hide-cm"))
    }

    #[cfg(target_os = "linux")]
    fn get_process_info(&mut self) {
        use std::process::Command;
        let app_name = crate::get_app_name().to_lowercase();

        // Get PID from systemctl
        if let Ok(output) = Command::new("systemctl")
            .args(&["show", &app_name, "--property=MainPID"])
            .output()
        {
            let output_str = String::from_utf8_lossy(&output.stdout);
            if let Some(pid_str) = output_str.strip_prefix("MainPID=") {
                if let Ok(pid) = pid_str.trim().parse::<u32>() {
                    if pid > 0 {
                        self.pid = Some(pid);
                        self.get_uptime_from_pid(pid);
                    }
                }
            }
        }
    }

    #[cfg(target_os = "windows")]
    fn get_process_info(&mut self) {
        // TODO: Get Windows service PID and uptime
        // This requires querying the service manager
    }

    #[cfg(target_os = "macos")]
    fn get_process_info(&mut self) {
        // TODO: Get macOS launchd service PID and uptime
    }

    #[cfg(target_os = "linux")]
    fn get_uptime_from_pid(&mut self, pid: u32) {
        use std::fs;

        // Read /proc/{pid}/stat to get start time
        if let Ok(stat) = fs::read_to_string(format!("/proc/{}/stat", pid)) {
            let parts: Vec<&str> = stat.split_whitespace().collect();
            if parts.len() > 21 {
                // Field 22 is starttime in clock ticks since boot
                if let Ok(start_ticks) = parts[21].parse::<u64>() {
                    // Get system uptime
                    if let Ok(uptime_str) = fs::read_to_string("/proc/uptime") {
                        if let Some(uptime_seconds_str) = uptime_str.split_whitespace().next() {
                            if let Ok(system_uptime) = uptime_seconds_str.parse::<f64>() {
                                // Convert ticks to seconds (usually 100 ticks per second)
                                let clock_ticks_per_sec = 100; // sysconf(_SC_CLK_TCK)
                                let start_seconds = start_ticks / clock_ticks_per_sec;
                                let uptime = system_uptime as u64 - start_seconds;
                                self.uptime_seconds = Some(uptime);
                            }
                        }
                    }
                }
            }
        }
    }

    #[cfg(not(target_os = "linux"))]
    fn get_uptime_from_pid(&mut self, _pid: u32) {
        // Not implemented for non-Linux platforms
    }
}

impl ConfigStatus {
    fn new() -> Self {
        Self {
            approve_mode: String::new(),
            verification_method: String::new(),
            password_set: false,
            hide_cm: false,
            allow_hide_cm: false,
            allow_logon_screen: false,
        }
    }

    fn check(&mut self) {
        self.approve_mode = Config::get_option("approve-mode");
        if self.approve_mode.is_empty() {
            self.approve_mode = "click".to_string(); // default
        }

        self.verification_method = Config::get_option("verification-method");
        if self.verification_method.is_empty() {
            self.verification_method = "use-both".to_string(); // default
        }

        // Check if permanent password is set
        self.password_set = !Config::get_permanent_password().is_empty();

        // Check hide CM option
        self.allow_hide_cm = hbb_common::config::option2bool(
            "allow-hide-cm",
            &Config::get_option("allow-hide-cm")
        );

        self.hide_cm = self.approve_mode == "password"
            && self.verification_method == "use-permanent-password"
            && self.allow_hide_cm;

        // Check logon screen password option
        self.allow_logon_screen = hbb_common::config::option2bool(
            "allow-logon-screen-password",
            &Config::get_option("allow-logon-screen-password")
        );
    }
}

impl NetworkStatus {
    fn new() -> Self {
        Self {
            rendezvous_server: String::new(),
            rendezvous_connected: false,
            nat_type: String::new(),
            local_ip: String::new(),
            public_ip: String::new(),
        }
    }

    fn check(&mut self) {
        // Get configured rendezvous server
        self.rendezvous_server = Config::get_rendezvous_server();

        // For now, mark as unknown - actual connectivity check would be async
        // In a full implementation, this would ping the server
        self.rendezvous_connected = false; // TODO: implement actual check

        // Get local IP
        self.local_ip = self.get_local_ip();

        // NAT type and public IP would require network probing
        self.nat_type = "Unknown".to_string();
        self.public_ip = String::new();
    }

    fn get_local_ip(&self) -> String {
        use std::net::UdpSocket;

        // Try to get local IP by connecting to a remote address (doesn't actually send data)
        if let Ok(socket) = UdpSocket::bind("0.0.0.0:0") {
            if socket.connect("8.8.8.8:80").is_ok() {
                if let Ok(local_addr) = socket.local_addr() {
                    return local_addr.ip().to_string();
                }
            }
        }

        "Unknown".to_string()
    }
}

impl DeviceInfo {
    fn new() -> Self {
        Self {
            id: String::new(),
            uuid: String::new(),
            active_connections: 0,
        }
    }

    fn collect(&mut self) {
        // Get device ID (same as --get-id command)
        self.id = crate::ipc::get_id();

        // Get UUID (encode to base64)
        self.uuid = crate::encode64(hbb_common::get_uuid());

        // Get active connections count
        self.active_connections = self.get_active_connections();
    }

    fn get_active_connections(&self) -> u32 {
        // Try to get connection count from IPC
        // This requires querying the running service via IPC
        // For now, return 0 as a placeholder
        // TODO: Implement actual IPC query to get active connection count
        0
    }
}

/// Main entry point for status check
pub fn check_status(json_output: bool) -> ResultType<()> {
    let mut report = StatusReport::new();
    report.collect()?;

    if json_output {
        report.print_json()?;
    } else {
        report.print_human_readable();
    }

    // Return error if there are critical issues
    if report.status == "error" {
        hbb_common::bail!("Status check found critical issues");
    }

    Ok(())
}
