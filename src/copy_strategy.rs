// Copy Strategy Module for Phase 2
// 复制策略模块：根据配置策略判断数据传输

use crate::config_manager::{ConfigManager, CopyStrategy};
use crate::data_transfer_filter;
use hbb_common::log;
use std::net::IpAddr;

/// 根据策略判断是否允许数据传输
pub fn should_allow_transfer(
    from_ip: &IpAddr,
    to_ip: &IpAddr,
    config_manager: &ConfigManager,
    _is_clipboard: bool,
) -> bool {
    // 获取源IP和目标IP的策略
    let from_strategy = config_manager.get_strategy_for_ip(from_ip);
    let to_strategy = config_manager.get_strategy_for_ip(to_ip);

    // 如果任何一方被拒绝，则不允许传输
    if from_strategy == CopyStrategy::Reject || to_strategy == CopyStrategy::Reject {
        log::warn!(
            "Transfer rejected: from={}, to={}, from_strategy={:?}, to_strategy={:?}",
            from_ip, to_ip, from_strategy, to_strategy
        );
        return false;
    }

    // 如果任何一方完全禁止复制，则不允许传输
    if from_strategy == CopyStrategy::NoCopy || to_strategy == CopyStrategy::NoCopy {
        log::warn!(
            "Transfer blocked by no-copy policy: from={}, to={}",
            from_ip, to_ip
        );
        return false;
    }

    // 如果允许双向复制，则直接允许
    if from_strategy == CopyStrategy::Bidirectional && to_strategy == CopyStrategy::Bidirectional {
        return true;
    }

    // 判断方向：from是服务端还是客户端
    // 在堡垒机模式中，服务端是内网IP，客户端是外网IP
    let from_is_server = data_transfer_filter::is_intranet_ip(from_ip);
    let to_is_server = data_transfer_filter::is_intranet_ip(to_ip);

    // 应用策略
    match from_strategy {
        CopyStrategy::ClientToServer => {
            // from允许客户端→服务端，所以from应该是客户端，to应该是服务端
            if from_is_server {
                log::warn!(
                    "Transfer blocked: from is server but strategy is client_to_server"
                );
                return false;
            }
            if !to_is_server {
                log::warn!(
                    "Transfer blocked: to is not server but strategy is client_to_server"
                );
                return false;
            }
            true
        }
        CopyStrategy::ServerToClient => {
            // from允许服务端→客户端，所以from应该是服务端，to应该是客户端
            if !from_is_server {
                log::warn!(
                    "Transfer blocked: from is not server but strategy is server_to_client"
                );
                return false;
            }
            if to_is_server {
                log::warn!(
                    "Transfer blocked: to is server but strategy is server_to_client"
                );
                return false;
            }
            true
        }
        _ => true,
    }
}

/// 检查是否应该拦截数据传输（基于data_transfer_filter的判断）
pub fn should_block_transfer(
    bytes: &[u8],
    from_ip: &IpAddr,
    to_ip: &IpAddr,
    config_manager: &ConfigManager,
) -> bool {
    // 首先检查是否是剪贴板或文件传输消息
    let is_clipboard = data_transfer_filter::might_be_clipboard_message(bytes);
    let is_file = data_transfer_filter::might_be_file_transfer_message(bytes);

    // 如果不是剪贴板或文件传输，则放行
    if !is_clipboard && !is_file {
        return false;
    }

    // 根据策略判断是否允许传输
    let allowed = should_allow_transfer(from_ip, to_ip, config_manager, is_clipboard);

    if !allowed {
        let transfer_type = if is_clipboard { "clipboard" } else { "file" };
        log::warn!(
            "Blocked {} transfer: from={}, to={}",
            transfer_type, from_ip, to_ip
        );
    }

    !allowed
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_intranet_ip() {
        let intranet_ip = "192.168.1.100".parse().unwrap();
        let internet_ip = "8.8.8.8".parse().unwrap();

        assert!(data_transfer_filter::is_intranet_ip(&intranet_ip));
        assert!(!data_transfer_filter::is_intranet_ip(&internet_ip));
    }
}
