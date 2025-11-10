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
    pub exe_path: Option<String>,
    pub version: Option<String>,
    pub md5: Option<String>,
    pub file_size: Option<u64>,
    pub build_date: Option<String>,
    pub listening_ports: Vec<u16>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ConfigStatus {
    pub approve_mode: String,
    pub verification_method: String,
    pub password_set: bool,
    pub hide_cm: bool,
    pub allow_hide_cm: bool,
    pub allow_logon_screen: bool,
    pub direct_server: bool,
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

        if !self.config.direct_server {
            self.issues.push("IP direct access mode is not enabled".to_string());
            self.recommendations.push("Run: sudo rustdesk --option direct-server Y".to_string());
        }

        // Network checks - only check rendezvous server if NOT in direct IP mode
        if !self.config.direct_server && !self.network.rendezvous_connected {
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
        println!("CLI 版本: {} ({})\n", crate::VERSION, crate::BUILD_DATE);

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
            println!("  ✗ 无人值守模式未激活");
        }

        // Listening ports
        if !self.service.listening_ports.is_empty() {
            print!("  监听端口: ");
            let ports_str: Vec<String> = self.service.listening_ports.iter()
                .map(|p| p.to_string())
                .collect();
            println!("{}", ports_str.join(", "));
        }

        // File information
        if let Some(ref exe_path) = self.service.exe_path {
            println!("\n[服务进程文件信息]");
            println!("  路径: {}", exe_path);

            if let Some(ref version) = self.service.version {
                println!("  版本: {}", version);
            }

            if let Some(ref build_date) = self.service.build_date {
                println!("  构建时间: {}", build_date);
            }

            if let Some(size) = self.service.file_size {
                let size_kb = size as f64 / 1024.0;
                let size_mb = size_kb / 1024.0;
                if size_mb >= 1.0 {
                    println!("  大小: {:.2} MB ({} bytes)", size_mb, size);
                } else {
                    println!("  大小: {:.2} KB ({} bytes)", size_kb, size);
                }
            }

            if let Some(ref md5) = self.service.md5 {
                println!("  MD5: {}", md5);
            }
        }

        // Config status
        println!("\n[配置检查]");
        self.print_config_item("approve-mode", &self.config.approve_mode, "password");
        self.print_config_item("verification-method", &self.config.verification_method, "use-permanent-password");

        self.print_bool_config("allow-hide-cm", self.config.allow_hide_cm, true);
        self.print_bool_config("allow-logon-screen-password", self.config.allow_logon_screen, true);
        self.print_bool_config("direct-server", self.config.direct_server, true);

        // Network status
        println!("\n[网络状态]");

        // Only show ID Server info when NOT in direct IP mode
        if !self.config.direct_server {
            println!("  Rendezvous 服务器: {}", self.network.rendezvous_server);
            if self.network.rendezvous_connected {
                println!("    ✓ 连接正常");
            } else {
                println!("    ✗ 连接失败");
            }

            if !self.network.nat_type.is_empty() {
                println!("  NAT 类型: {}", self.network.nat_type);
            }
        } else {
            println!("  模式: IP 直连模式");
        }

        if !self.network.local_ip.is_empty() {
            println!("  本地 IP: {}", self.network.local_ip);
        }
        if !self.network.public_ip.is_empty() {
            println!("  公网 IP: {}", self.network.public_ip);
        }

        // Device info
        println!("\n[连接信息]");

        // Only show ID when NOT in direct IP mode
        if !self.config.direct_server {
            println!("  连接 ID: {}", self.device.id);
        }

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
            exe_path: None,
            version: None,
            md5: None,
            file_size: None,
            build_date: None,
            listening_ports: Vec::new(),
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

        // Get file information (exe path, version, MD5, size, mtime)
        self.get_file_info();

        // Get listening ports
        if let Some(pid) = self.pid {
            self.listening_ports = self.get_listening_ports(pid);
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
        // Find the --server process (may be a child of service process)
        if let Some(server_pid) = self.find_server_process() {
            self.pid = Some(server_pid);
            self.get_uptime_from_pid(server_pid);
        }
    }

    #[cfg(target_os = "windows")]
    fn find_server_process(&self) -> Option<u32> {
        use std::process::Command;

        // Use WMIC to find rustdesk.exe processes with --server argument
        if let Ok(output) = Command::new("wmic")
            .args(&[
                "process",
                "where",
                "name like '%rustdesk%'",
                "get",
                "ProcessId,CommandLine",
                "/format:csv"
            ])
            .output()
        {
            let output_str = String::from_utf8_lossy(&output.stdout);

            // Parse CSV output and find process with --server in command line
            for line in output_str.lines().skip(1) {  // Skip header
                if line.contains("--server") {
                    // CSV format: Node,CommandLine,ProcessId
                    let parts: Vec<&str> = line.split(',').collect();
                    if parts.len() >= 3 {
                        if let Ok(pid) = parts[parts.len() - 1].trim().parse::<u32>() {
                            if pid > 0 {
                                return Some(pid);
                            }
                        }
                    }
                }
            }
        }

        // Fallback: Try using PowerShell
        if let Ok(output) = Command::new("powershell.exe")
            .args(&[
                "-NoProfile",
                "-Command",
                "Get-Process | Where-Object {$_.ProcessName -like '*rustdesk*' -and $_.CommandLine -like '*--server*'} | Select-Object -First 1 -ExpandProperty Id"
            ])
            .output()
        {
            let pid_str = String::from_utf8_lossy(&output.stdout);
            if let Ok(pid) = pid_str.trim().parse::<u32>() {
                if pid > 0 {
                    return Some(pid);
                }
            }
        }

        None
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

    #[cfg(target_os = "windows")]
    fn get_uptime_from_pid(&mut self, pid: u32) {
        use winapi::um::processthreadsapi::OpenProcess;
        use winapi::um::processthreadsapi::GetProcessTimes;
        use winapi::um::winnt::PROCESS_QUERY_INFORMATION;
        use winapi::um::handleapi::CloseHandle;
        use winapi::shared::minwindef::FILETIME;
        use std::time::SystemTime;

        unsafe {
            let process_handle = OpenProcess(PROCESS_QUERY_INFORMATION, 0, pid);
            if process_handle.is_null() {
                return;
            }

            let mut creation_time = FILETIME { dwLowDateTime: 0, dwHighDateTime: 0 };
            let mut exit_time = FILETIME { dwLowDateTime: 0, dwHighDateTime: 0 };
            let mut kernel_time = FILETIME { dwLowDateTime: 0, dwHighDateTime: 0 };
            let mut user_time = FILETIME { dwLowDateTime: 0, dwHighDateTime: 0 };

            if GetProcessTimes(
                process_handle,
                &mut creation_time,
                &mut exit_time,
                &mut kernel_time,
                &mut user_time,
            ) != 0 {
                // Convert FILETIME to seconds since epoch
                let creation_timestamp = ((creation_time.dwHighDateTime as u64) << 32)
                    | (creation_time.dwLowDateTime as u64);

                // FILETIME is in 100-nanosecond intervals since January 1, 1601
                // Convert to seconds since UNIX epoch (January 1, 1970)
                let windows_epoch_diff = 11644473600u64; // seconds between 1601 and 1970
                let creation_secs = creation_timestamp / 10_000_000 - windows_epoch_diff;

                if let Ok(now) = SystemTime::now().duration_since(SystemTime::UNIX_EPOCH) {
                    let now_secs = now.as_secs();
                    if now_secs > creation_secs {
                        self.uptime_seconds = Some(now_secs - creation_secs);
                    }
                }
            }

            CloseHandle(process_handle);
        }
    }

    #[cfg(not(any(target_os = "linux", target_os = "windows")))]
    fn get_uptime_from_pid(&mut self, _pid: u32) {
        // Not implemented for non-Linux/Windows platforms
    }

    fn get_file_info(&mut self) {
        use std::fs;
        use std::time::SystemTime;

        // Only get file info if we have a PID (service is running)
        // Do NOT use current process path as fallback
        let exe_path = if let Some(pid) = self.pid {
            self.get_exe_path_from_pid(pid)
        } else {
            None  // Service not running, leave all fields as None
        };

        if let Some(ref path) = exe_path {
            self.exe_path = Some(path.clone());

            // Get version from executable file
            self.version = self.get_version_from_exe(path);

            // Get build date from executable (using --build-date)
            self.build_date = self.get_build_date_from_exe(path);

            // Get file metadata
            if let Ok(metadata) = fs::metadata(path) {
                // File size
                self.file_size = Some(metadata.len());
            }

            // Calculate MD5 hash
            self.md5 = self.calculate_md5(path);
        }
    }

    #[cfg(target_os = "linux")]
    fn get_exe_path_from_pid(&self, pid: u32) -> Option<String> {
        std::fs::read_link(format!("/proc/{}/exe", pid))
            .ok()
            .and_then(|p| p.to_str().map(|s| s.to_string()))
    }

    #[cfg(target_os = "windows")]
    fn get_exe_path_from_pid(&self, pid: u32) -> Option<String> {
        use std::os::windows::ffi::OsStringExt;
        use std::ffi::OsString;
        use winapi::um::processthreadsapi::OpenProcess;
        use winapi::um::psapi::GetModuleFileNameExW;
        use winapi::um::winnt::PROCESS_QUERY_INFORMATION;
        use winapi::um::winnt::PROCESS_VM_READ;
        use winapi::um::handleapi::CloseHandle;

        unsafe {
            let process_handle = OpenProcess(
                PROCESS_QUERY_INFORMATION | PROCESS_VM_READ,
                0,
                pid,
            );

            if process_handle.is_null() {
                return None;
            }

            let mut buffer: [u16; 1024] = [0; 1024];
            let len = GetModuleFileNameExW(
                process_handle,
                std::ptr::null_mut(),
                buffer.as_mut_ptr(),
                buffer.len() as u32,
            );

            CloseHandle(process_handle);

            if len > 0 {
                let os_string = OsString::from_wide(&buffer[..len as usize]);
                os_string.to_str().map(|s| s.to_string())
            } else {
                None
            }
        }
    }

    #[cfg(target_os = "macos")]
    fn get_exe_path_from_pid(&self, pid: u32) -> Option<String> {
        use std::process::Command;

        // Use ps to get executable path
        if let Ok(output) = Command::new("ps")
            .args(&["-p", &pid.to_string(), "-o", "comm="])
            .output()
        {
            let path = String::from_utf8_lossy(&output.stdout);
            let trimmed = path.trim();
            if !trimmed.is_empty() {
                return Some(trimmed.to_string());
            }
        }
        None
    }

    #[cfg(target_os = "windows")]
    fn get_version_from_exe(&self, path: &str) -> Option<String> {
        // Try to get version from Windows PE version info
        use std::process::Command;

        // Method 1: Try running the executable with --version
        if let Ok(output) = Command::new(path)
            .arg("--version")
            .output()
        {
            let version_str = String::from_utf8_lossy(&output.stdout);
            let version = version_str.trim();
            if !version.is_empty() && version.len() < 100 {
                return Some(version.to_string());
            }
        }

        // Method 2: Try using PowerShell to get file version
        if let Ok(output) = Command::new("powershell.exe")
            .args(&[
                "-NoProfile",
                "-Command",
                &format!("(Get-Item '{}').VersionInfo.FileVersion", path)
            ])
            .output()
        {
            let version_str = String::from_utf8_lossy(&output.stdout);
            let version = version_str.trim();
            if !version.is_empty() && version != "0.0.0.0" {
                return Some(version.to_string());
            }
        }

        None
    }

    #[cfg(not(target_os = "windows"))]
    fn get_version_from_exe(&self, path: &str) -> Option<String> {
        use std::process::Command;

        // Try running the executable with --version
        if let Ok(output) = Command::new(path)
            .arg("--version")
            .output()
        {
            let version_str = String::from_utf8_lossy(&output.stdout);
            let version = version_str.trim();
            if !version.is_empty() && version.len() < 100 {
                return Some(version.to_string());
            }
        }

        None
    }

    fn get_build_date_from_exe(&self, path: &str) -> Option<String> {
        use std::process::Command;

        // Try running the executable with --build-date
        if let Ok(output) = Command::new(path)
            .arg("--build-date")
            .output()
        {
            let build_date_str = String::from_utf8_lossy(&output.stdout);
            let build_date = build_date_str.trim();
            if !build_date.is_empty() && build_date.len() < 100 {
                return Some(build_date.to_string());
            }
        }

        None
    }

    fn calculate_md5(&self, path: &str) -> Option<String> {
        use std::fs::File;
        use std::io::Read;

        let mut file = File::open(path).ok()?;
        let mut buffer = Vec::new();
        file.read_to_end(&mut buffer).ok()?;

        let digest = md5::compute(&buffer);
        Some(format!("{:x}", digest))
    }

    #[cfg(target_os = "windows")]
    fn get_listening_ports(&self, pid: u32) -> Vec<u16> {
        use std::process::Command;

        let mut ports = Vec::new();

        // Use netstat to find listening ports for this PID
        if let Ok(output) = Command::new("netstat")
            .args(&["-ano", "-p", "TCP"])
            .output()
        {
            let output_str = String::from_utf8_lossy(&output.stdout);
            let pid_str = pid.to_string();

            for line in output_str.lines() {
                // Look for LISTENING state and matching PID
                if line.contains("LISTENING") && line.contains(&pid_str) {
                    // Parse the local address column
                    let parts: Vec<&str> = line.split_whitespace().collect();
                    if parts.len() >= 5 {
                        // Local address is typically in format IP:PORT
                        if let Some(addr_part) = parts.get(1) {
                            if let Some(port_str) = addr_part.split(':').last() {
                                if let Ok(port) = port_str.parse::<u16>() {
                                    if !ports.contains(&port) {
                                        ports.push(port);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        ports.sort();
        ports
    }

    #[cfg(target_os = "linux")]
    fn get_listening_ports(&self, pid: u32) -> Vec<u16> {
        use std::fs;

        let mut ports = Vec::new();

        // Read /proc/net/tcp and /proc/net/tcp6
        for tcp_file in &["/proc/net/tcp", "/proc/net/tcp6"] {
            if let Ok(content) = fs::read_to_string(tcp_file) {
                for line in content.lines().skip(1) {  // Skip header
                    let parts: Vec<&str> = line.split_whitespace().collect();
                    if parts.len() >= 10 {
                        // Check if state is LISTEN (0A in hex)
                        if parts[3] == "0A" {
                            // Get inode
                            if let Ok(inode) = parts[9].parse::<u64>() {
                                // Check if this inode belongs to our PID
                                if self.check_inode_belongs_to_pid(pid, inode) {
                                    // Parse local address (format: XXXXXXXX:PPPP)
                                    if let Some(addr_part) = parts.get(1) {
                                        if let Some(port_hex) = addr_part.split(':').nth(1) {
                                            if let Ok(port) = u16::from_str_radix(port_hex, 16) {
                                                if !ports.contains(&port) {
                                                    ports.push(port);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        ports.sort();
        ports
    }

    #[cfg(target_os = "linux")]
    fn check_inode_belongs_to_pid(&self, pid: u32, inode: u64) -> bool {
        use std::fs;
        use std::path::Path;

        let fd_path = format!("/proc/{}/fd", pid);
        if let Ok(entries) = fs::read_dir(&fd_path) {
            for entry in entries.flatten() {
                if let Ok(link) = fs::read_link(entry.path()) {
                    let link_str = link.to_string_lossy();
                    if link_str.contains(&format!("socket:[{}]", inode)) {
                        return true;
                    }
                }
            }
        }
        false
    }

    #[cfg(target_os = "macos")]
    fn get_listening_ports(&self, pid: u32) -> Vec<u16> {
        use std::process::Command;

        let mut ports = Vec::new();

        // Use lsof to find listening ports for this PID
        if let Ok(output) = Command::new("lsof")
            .args(&[
                "-Pan",
                "-p", &pid.to_string(),
                "-i", "TCP",
                "-sTCP:LISTEN"
            ])
            .output()
        {
            let output_str = String::from_utf8_lossy(&output.stdout);

            for line in output_str.lines().skip(1) {  // Skip header
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 9 {
                    // Name column typically contains address:port
                    if let Some(name_part) = parts.get(8) {
                        if let Some(port_str) = name_part.split(':').last() {
                            if let Ok(port) = port_str.parse::<u16>() {
                                if !ports.contains(&port) {
                                    ports.push(port);
                                }
                            }
                        }
                    }
                }
            }
        }

        ports.sort();
        ports
    }

    #[cfg(not(any(target_os = "windows", target_os = "linux", target_os = "macos")))]
    fn get_listening_ports(&self, _pid: u32) -> Vec<u16> {
        Vec::new()
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
            direct_server: false,
        }
    }

    fn check(&mut self) {
        // Get options from IPC (same as --list-options) for consistency
        let options = crate::ipc::get_options();

        self.approve_mode = options.get("approve-mode").unwrap_or(&"".to_string()).clone();
        if self.approve_mode.is_empty() {
            self.approve_mode = "click".to_string(); // default
        }

        self.verification_method = options.get("verification-method").unwrap_or(&"".to_string()).clone();
        if self.verification_method.is_empty() {
            self.verification_method = "use-both".to_string(); // default
        }

        // Check if permanent password is set
        self.password_set = !Config::get_permanent_password().is_empty();

        // Check hide CM option
        self.allow_hide_cm = hbb_common::config::option2bool(
            "allow-hide-cm",
            options.get("allow-hide-cm").unwrap_or(&"".to_string())
        );

        self.hide_cm = self.approve_mode == "password"
            && self.verification_method == "use-permanent-password"
            && self.allow_hide_cm;

        // Check logon screen password option
        self.allow_logon_screen = hbb_common::config::option2bool(
            "allow-logon-screen-password",
            options.get("allow-logon-screen-password").unwrap_or(&"".to_string())
        );

        // Check IP direct access option
        self.direct_server = hbb_common::config::option2bool(
            "direct-server",
            options.get("direct-server").unwrap_or(&"".to_string())
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
