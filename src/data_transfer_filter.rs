// Data Transfer Filter for One-Way Copy
// 用于在中继服务器层面拦截内网到外网的数据传输（剪贴板+文件）

use std::net::IpAddr;

/// 判断IP是否为内网地址
pub fn is_intranet_ip(ip: &IpAddr) -> bool {
    match ip {
        IpAddr::V4(ip) => ip.is_private(),
        IpAddr::V6(_) => false,
    }
}

/// 快速检查字节数据是否可能是剪贴板消息
/// 基于rustdesk协议的剪贴板消息特征
pub fn might_be_clipboard_message(bytes: &[u8]) -> bool {
    if bytes.len() < 2 {
        return false;
    }
    // 剪贴板消息通常以这些字节开头
    bytes.windows(2).any(|w| matches!(w[0], 0x82 | 0xA2 | 0xE2))
}

/// 快速检查字节数据是否可能是文件传输消息
/// 基于rustdesk协议的文件传输消息特征
pub fn might_be_file_transfer_message(bytes: &[u8]) -> bool {
    if bytes.len() < 2 {
        return false;
    }
    
    // 文件传输消息的特征字节
    // 这些是基于rustdesk协议分析的初步判断，需要通过实际测试验证
    
    // 初步的文件传输识别策略：
    // 1. 检查是否有文件传输相关的字节特征
    // 2. 文件传输通常是大数据块（>1024字节）
    // 3. 可能有特定的消息类型标识
    
    // 方法1：基于消息类型字节
    // 注意：这些值需要通过协议分析或实际抓包验证
    let file_transfer_markers = [0x83, 0x84, 0x85, 0x86]; // 假设的文件传输标记
    
    // 方法2：基于数据大小（文件传输通常是大块数据）
    let is_large_data = bytes.len() > 1024;
    
    // 方法3：检查特定的字节模式
    let has_file_marker = bytes.windows(2).any(|w| {
        file_transfer_markers.contains(&w[0])
    });
    
    // 综合判断：如果有文件传输标记，或者数据量很大，可能是文件传输
    has_file_marker || (is_large_data && !might_be_clipboard_message(bytes))
}

/// 决定是否应该拦截数据传输（剪贴板+文件）
pub fn should_block_data_transfer(bytes: &[u8], from_intranet: bool) -> bool {
    if !from_intranet {
        return false;
    }
    
    // 检查是否是剪贴板消息
    if might_be_clipboard_message(bytes) {
        return true;
    }
    
    // 检查是否是文件传输消息
    if might_be_file_transfer_message(bytes) {
        return true;
    }
    
    false
}

/// 保留旧函数以兼容现有代码
pub fn should_block_clipboard(bytes: &[u8], from_intranet: bool) -> bool {
    should_block_data_transfer(bytes, from_intranet)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::{IpAddr, Ipv4Addr};

    #[test]
    fn test_is_intranet_ip() {
        assert!(is_intranet_ip(&IpAddr::V4(Ipv4Addr::new(192, 168, 1, 1))));
        assert!(is_intranet_ip(&IpAddr::V4(Ipv4Addr::new(10, 0, 0, 1))));
        assert!(!is_intranet_ip(&IpAddr::V4(Ipv4Addr::new(8, 8, 8, 8))));
    }
    
    #[test]
    fn test_file_transfer_detection() {
        // 测试文件传输识别
        let large_data = vec![0u8; 2048]; // 2KB数据
        assert!(might_be_file_transfer_message(&large_data));
        
        let small_data = vec![0u8; 512]; // 512B数据
        assert!(!might_be_file_transfer_message(&small_data));
    }
    
    #[test]
    fn test_data_transfer_blocking() {
        let clipboard_bytes = vec![0x82, 0x00, 0x01, 0x02];
        let file_bytes = vec![0u8; 2048];
        let control_bytes = vec![0x00, 0x01, 0x02, 0x03];
        
        // 内网->外网，剪贴板：拦截
        assert!(should_block_data_transfer(&clipboard_bytes, true));
        
        // 内网->外网，文件：拦截
        assert!(should_block_data_transfer(&file_bytes, true));
        
        // 内网->外网，控制消息：放行
        assert!(!should_block_data_transfer(&control_bytes, true));
        
        // 外网->内网，所有消息：放行
        assert!(!should_block_data_transfer(&clipboard_bytes, false));
        assert!(!should_block_data_transfer(&file_bytes, false));
        assert!(!should_block_data_transfer(&control_bytes, false));
    }
}
