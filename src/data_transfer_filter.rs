//! Data Transfer Filter Module
//! 
//! This module provides functionality to filter clipboard and file transfer messages
//! based on network direction (intranet vs internet) for security purposes.

use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};

/// Check if an IP address is an intranet (private) address
/// 
/// # IPv4 Private Ranges
/// - 10.0.0.0/8
/// - 172.16.0.0/12
/// - 192.168.0.0/16
/// - 169.254.0.0/16 (link-local)
/// 
/// # IPv6 Private Ranges
/// - fc00::/7 (Unique Local Addresses)
/// - fe80::/10 (Link-Local Addresses)
/// - ::1/128 (Loopback)
pub fn is_intranet_ip(ip: &IpAddr) -> bool {
    match ip {
        IpAddr::V4(ipv4) => is_intranet_ipv4(ipv4),
        IpAddr::V6(ipv6) => is_intranet_ipv6(ipv6),
    }
}

/// Check if an IPv4 address is an intranet address
fn is_intranet_ipv4(ip: &Ipv4Addr) -> bool {
    let octets = ip.octets();
    
    // 10.0.0.0/8
    if octets[0] == 10 {
        return true;
    }
    
    // 172.16.0.0/12
    if octets[0] == 172 && (16..=31).contains(&octets[1]) {
        return true;
    }
    
    // 192.168.0.0/16
    if octets[0] == 192 && octets[1] == 168 {
        return true;
    }
    
    // 169.254.0.0/16 (link-local)
    if octets[0] == 169 && octets[1] == 254 {
        return true;
    }
    
    // 127.0.0.0/8 (loopback)
    if octets[0] == 127 {
        return true;
    }
    
    false
}

/// Check if an IPv6 address is an intranet address
/// 
/// # IPv6 Private Ranges
/// - fc00::/7 (Unique Local Addresses) - fc00::/8 and fd00::/8
/// - fe80::/10 (Link-Local Addresses)
/// - ::1/128 (Loopback)
fn is_intranet_ipv6(ip: &Ipv6Addr) -> bool {
    let segments = ip.segments();
    
    // fc00::/7 (Unique Local Addresses)
    // fc00::/8 (fc00-7fff) and fd00::/8 (fd00-ffff)
    if (segments[0] & 0xfe00) == 0xfc00 {
        return true;
    }
    
    // fe80::/10 (Link-Local Addresses)
    if (segments[0] & 0xffc0) == 0xfe80 {
        return true;
    }
    
    // ::1/128 (Loopback)
    if ip.is_loopback() {
        return true;
    }
    
    false
}

/// Check if data bytes represent a clipboard message
/// 
/// # Clipboard Message Signatures
/// Based on protobuf encoding, clipboard messages have specific byte patterns:
/// - MultiClipboards message starts with field 1 (repeated Clipboard)
/// - Field number 1 with wire type 2 (length-delimited) = 0x0A
/// 
/// # Note
/// This is a heuristic check. For accurate detection, parse the protobuf message.
pub fn is_clipboard_message(data: &[u8]) -> bool {
    if data.is_empty() {
        return false;
    }
    
    // Check for MultiClipboards message signature
    // Field 1, wire type 2 (length-delimited) = 0x0A
    if data[0] == 0x0A {
        return true;
    }
    
    // Alternative signatures for different protobuf encodings
    // Field 2, wire type 2 = 0x12
    if data.len() > 1 && data[0] == 0x12 {
        return true;
    }
    
    false
}

/// Check if data bytes represent a file transfer message
/// 
/// # File Transfer Message Signatures
/// Based on protobuf encoding, file transfer messages have specific byte patterns:
/// - FileTransfer message has specific field IDs
/// 
/// # Note
/// This is a heuristic check. For accurate detection, parse the protobuf message.
pub fn is_file_transfer_message(data: &[u8]) -> bool {
    if data.is_empty() {
        return false;
    }
    
    // Check for FileTransfer message signature
    // Field 1, wire type 2 (length-delimited) = 0x0A (same as clipboard)
    // Field 2, wire type 2 = 0x12
    // We need more specific patterns to distinguish from clipboard
    
    // File transfer typically has larger payloads
    // This is a heuristic, needs proper protobuf parsing
    if data.len() > 100 {
        return true;
    }
    
    false
}

/// Determine if data transfer should be blocked based on direction
/// 
/// # Parameters
/// - `data`: The data bytes to check
/// - `source_ip`: Source IP address
/// - `dest_ip`: Destination IP address
/// 
/// # Returns
/// - `true`: Block the transfer (intranet → internet)
/// - `false`: Allow the transfer (internet → intranet or same network type)
/// 
/// # Security Policy
/// - Block: Intranet → Internet
/// - Allow: Internet → Intranet
/// - Allow: Intranet → Intranet
/// - Allow: Internet → Internet
pub fn should_block_transfer(data: &[u8], source_ip: &IpAddr, dest_ip: &IpAddr) -> bool {
    // Check if this is clipboard or file transfer data
    if !is_clipboard_message(data) && !is_file_transfer_message(data) {
        // Not a data transfer message, allow
        return false;
    }
    
    // Check direction
    let source_is_intranet = is_intranet_ip(source_ip);
    let dest_is_intranet = is_intranet_ip(dest_ip);
    
    // Block: Intranet → Internet
    // Allow: Internet → Intranet
    // Allow: Intranet → Intranet
    // Allow: Internet → Internet
    source_is_intranet && !dest_is_intranet
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_intranet_ipv4() {
        // Test private IPv4 ranges
        assert!(is_intranet_ipv4(&Ipv4Addr::new(10, 0, 0, 1)));
        assert!(is_intranet_ipv4(&Ipv4Addr::new(10, 255, 255, 255)));
        assert!(is_intranet_ipv4(&Ipv4Addr::new(172, 16, 0, 1)));
        assert!(is_intranet_ipv4(&Ipv4Addr::new(172, 31, 255, 255)));
        assert!(is_intranet_ipv4(&Ipv4Addr::new(192, 168, 0, 1)));
        assert!(is_intranet_ipv4(&Ipv4Addr::new(192, 168, 255, 255)));
        assert!(is_intranet_ipv4(&Ipv4Addr::new(169, 254, 0, 1)));
        assert!(is_intranet_ipv4(&Ipv4Addr::new(127, 0, 0, 1)));
        
        // Test public IPv4 addresses
        assert!(!is_intranet_ipv4(&Ipv4Addr::new(8, 8, 8, 8)));
        assert!(!is_intranet_ipv4(&Ipv4Addr::new(1, 1, 1, 1)));
        assert!(!is_intranet_ipv4(&Ipv4Addr::new(172, 15, 0, 1)));
        assert!(!is_intranet_ipv4(&Ipv4Addr::new(172, 32, 0, 1)));
    }

    #[test]
    fn test_is_intranet_ipv6() {
        // Test private IPv6 ranges
        assert!(is_intranet_ipv6(&Ipv6Addr::new(0xfc00, 0, 0, 0, 0, 0, 0, 1)));
        assert!(is_intranet_ipv6(&Ipv6Addr::new(0xfd00, 0, 0, 0, 0, 0, 0, 1)));
        assert!(is_intranet_ipv6(&Ipv6Addr::new(0xfe80, 0, 0, 0, 0, 0, 0, 1)));
        assert!(is_intranet_ipv6(&Ipv6Addr::new(0, 0, 0, 0, 0, 0, 0, 1)));
        
        // Test public IPv6 addresses
        assert!(!is_intranet_ipv6(&Ipv6Addr::new(0x2001, 0x4860, 0x4860, 0, 0, 0, 0, 0x8888)));
    }

    #[test]
    fn test_is_intranet_ip() {
        // Test IPv4
        assert!(is_intranet_ip(&IpAddr::V4(Ipv4Addr::new(192, 168, 1, 1))));
        assert!(!is_intranet_ip(&IpAddr::V4(Ipv4Addr::new(8, 8, 8, 8))));
        
        // Test IPv6
        assert!(is_intranet_ip(&IpAddr::V6(Ipv6Addr::new(0xfc00, 0, 0, 0, 0, 0, 0, 1))));
        assert!(!is_intranet_ip(&IpAddr::V6(Ipv6Addr::new(0x2001, 0x4860, 0x4860, 0, 0, 0, 0, 0x8888))));
    }

    #[test]
    fn test_is_clipboard_message() {
        // Test empty data
        assert!(!is_clipboard_message(&[]));
        
        // Test clipboard message signature
        assert!(is_clipboard_message(&[0x0A, 0x10, 0x00]));
        assert!(is_clipboard_message(&[0x12, 0x05, 0x00]));
        
        // Test non-clipboard data
        assert!(!is_clipboard_message(&[0x00, 0x01, 0x02]));
    }

    #[test]
    fn test_is_file_transfer_message() {
        // Test empty data
        assert!(!is_file_transfer_message(&[]));
        
        // Test small data
        assert!(!is_file_transfer_message(&[0x0A, 0x01, 0x02]));
        
        // Test large data (heuristic)
        let large_data = vec![0u8; 200];
        assert!(is_file_transfer_message(&large_data));
    }

    #[test]
    fn test_should_block_transfer() {
        let clipboard_data = vec![0x0A, 0x10, 0x00];
        
        // Intranet → Internet: Block
        let intranet_ip = IpAddr::V4(Ipv4Addr::new(192, 168, 1, 1));
        let internet_ip = IpAddr::V4(Ipv4Addr::new(8, 8, 8, 8));
        assert!(should_block_transfer(&clipboard_data, &intranet_ip, &internet_ip));
        
        // Internet → Intranet: Allow
        assert!(!should_block_transfer(&clipboard_data, &internet_ip, &intranet_ip));
        
        // Intranet → Intranet: Allow
        let intranet_ip2 = IpAddr::V4(Ipv4Addr::new(10, 0, 0, 1));
        assert!(!should_block_transfer(&clipboard_data, &intranet_ip, &intranet_ip2));
        
        // Internet → Internet: Allow
        let internet_ip2 = IpAddr::V4(Ipv4Addr::new(1, 1, 1, 1));
        assert!(!should_block_transfer(&clipboard_data, &internet_ip, &internet_ip2));
    }

    #[test]
    fn test_edge_cases() {
        // Empty data
        assert!(!is_clipboard_message(&[]));
        assert!(!is_file_transfer_message(&[]));
        
        // Single byte
        assert!(!is_clipboard_message(&[0x0A])); // No length following
        assert!(!is_file_transfer_message(&[0x0A]));
        
        // IPv6 edge cases
        assert!(is_intranet_ipv6(&Ipv6Addr::LOCALHOST));
        assert!(!is_intranet_ipv6(&Ipv6Addr::new(0x2001, 0xdb8, 0, 0, 0, 0, 0, 0))); // Documentation range
    }
}
