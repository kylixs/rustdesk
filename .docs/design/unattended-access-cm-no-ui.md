# 无人值守模式 CM 窗口隐藏设计方案

## 1. 业务需求

**目标**：在无人值守模式下，被控端用户无法通过操作连接管理器（CM）窗口来断开远程连接或关闭窗口，确保远程桌面连接的稳定性。

**用户场景**：
- 管理员配置了无人值守访问模式（approve-mode=password, verification-method=use-permanent-password, allow-hide-cm=Y）
- 远程用户通过密码连接到被控端
- 被控端用户不应看到 CM 窗口，也无法通过窗口操作断开连接

## 2. 技术背景

### 2.1 CM（Connection Manager）窗口架构

RustDesk 的连接管理器有两种启动模式：

1. **`--cm` 模式（带 UI）**
   - 启动独立进程：`rustdesk --cm`
   - 显示 Flutter 窗口，用户可见
   - 用户可以通过窗口断开连接、修改权限等

2. **`--cm-no-ui` 模式（无 UI）**
   - 启动独立进程：`rustdesk --cm-no-ui`
   - 后台运行，不显示窗口
   - 提供完整的 IPC 功能（文件传输、剪贴板、日志等）
   - 用户无法通过 UI 操作

### 2.2 当前实现（提交 645fc82）

**文件**：`src/server/connection.rs`

**问题**：
```rust
fn try_start_cm(&mut self, peer_id: String, name: String, authorized: bool) {
    if self.is_unattended_access_mode() {
        // 直接返回，跳过发送 Login 消息
        return;
    }
    self.send_to_cm(ipc::Data::Login { ... });
}
```

**缺陷**：
- ❌ 跳过 `try_start_cm()` 后，`ipc::Data::Login` 消息未发送到 CM
- ❌ 但 `try_start_cm_ipc()` 仍会启动 `--cm` 进程（带 UI）
- ❌ CM 进程没有收到初始化消息，状态不一致
- ❌ 后续的文件传输、剪贴板等消息发送到未初始化的 CM
- ⚠️ 可能导致连接不稳定、功能异常

### 2.3 启动流程对比

#### 正常模式（--cm）
```
Connection::handle_login_request
  ↓
try_start_cm_ipc()
  ↓
start_ipc() @ connection.rs:4355
  ↓
启动新进程: rustdesk --cm
  ↓
显示 CM 窗口（用户可见）
  ↓
IPC 通信: Connection ↔ CM 进程
```

#### --cm-no-ui 模式（独立启动）
```
命令行: rustdesk --cm-no-ui
  ↓
core_main.rs:643
  ↓
flutter::connection_manager::start_cm_no_ui()
  ↓
ui_cm_interface::start_ipc(ConnectionManager)
  ↓
监听 IPC "_cm"，无窗口
  ↓
处理来自 Connection 的消息
```

## 3. 解决方案

### 3.1 设计原则

1. **最小改动原则**：只修改启动参数，不改变架构
2. **功能完整性**：保留所有 IPC 功能（文件传输、剪贴板等）
3. **进程隔离**：继续使用独立进程模式，保证稳定性
4. **用户体验**：无人值守模式下用户完全看不到 CM 窗口

### 3.2 实施方案

**修改点**：`src/server/connection.rs:4375` 的 `start_ipc()` 函数

**核心逻辑**：
- 无人值守模式：启动 `--cm-no-ui` 进程
- 正常模式：启动 `--cm` 进程

**代码修改**：

```rust
// src/server/connection.rs:4373-4401

#[allow(unused_mut)]
#[allow(unused_assignments)]
let mut args = vec!["--cm"];  // 默认带 UI
#[allow(unused_mut)]
#[cfg(target_os = "linux")]
let mut user = None;

// Determine whether to use --cm or --cm-no-ui
let use_no_ui = {
    #[cfg(target_os = "linux")]
    {
        // Linux headless mode always uses --cm-no-ui
        crate::platform::is_headless_allowed() && linux_desktop_manager::is_headless()
    }
    #[cfg(not(target_os = "linux"))]
    {
        // Other platforms: check unattended access mode
        false  // Will be set below
    }
};

// Check unattended access mode for all platforms
let use_no_ui = use_no_ui || hbb_common::password_security::hide_cm();

if use_no_ui {
    args = vec!["--cm-no-ui"];
    log::info!("[UNATTENDED] Starting CM in no-ui mode");

    #[cfg(target_os = "linux")]
    {
        // Linux headless user setup
        if crate::platform::is_headless_allowed() && linux_desktop_manager::is_headless() {
            let mut username = linux_desktop_manager::get_username();
            loop {
                if !username.is_empty() {
                    break;
                }
                let _res = timeout(1_000, _rx_desktop_ready.recv()).await;
                username = linux_desktop_manager::get_username();
            }
            let uid = {
                let output = run_cmds(&format!("id -u {}", &username))?;
                let output = output.trim();
                if output.is_empty() || !output.parse::<i32>().is_ok() {
                    bail!("Invalid username {}", &username);
                }
                output.to_string()
            };
            user = Some((uid, username));
        }
    }
}
```

### 3.3 改动点统计

| 文件 | 函数 | 行号 | 改动 |
|------|------|------|------|
| `src/server/connection.rs` | `start_ipc()` | 4373-4401 | 修改启动参数逻辑 |

**改动量**：约 30 行代码

## 4. 方案对比

| 方案 | 改动量 | 功能完整性 | 稳定性 | 复杂度 | 用户体验 |
|------|--------|-----------|--------|--------|---------|
| **方案A：使用 --cm-no-ui** | ⭐⭐⭐⭐⭐ 最小 | ⭐⭐⭐⭐⭐ 完整 | ⭐⭐⭐⭐⭐ 高 | ⭐⭐⭐⭐⭐ 简单 | ⭐⭐⭐⭐⭐ 完全隐藏 |
| 方案B：跳过CM IPC | ⭐⭐⭐⭐ 较小 | ⭐⭐ 受损 | ⭐ 低 | ⭐⭐⭐ 中等 | ⭐⭐⭐⭐ 隐藏但功能受限 |
| 原提交645fc82 | ⭐⭐⭐⭐ 较小 | ⭐⭐ 受损 | ⭐ 低 | ⭐⭐⭐⭐ 简单 | ⭐⭐⭐⭐ 隐藏但不稳定 |

**选择**：方案A（使用 --cm-no-ui）

## 5. 测试计划

### 5.1 功能测试

| 测试项 | 正常模式 | 无人值守模式 |
|--------|---------|-------------|
| CM 窗口显示 | ✓ 显示 | ✗ 不显示 |
| 远程桌面控制 | ✓ | ✓ |
| 文件传输 | ✓ | ✓ |
| 剪贴板同步 | ✓ | ✓ |
| 语音通话 | ✓ | ✓ |
| 权限控制 | ✓ 用户可调整 | ✓ 配置固定 |
| 断开连接 | ✓ 用户可断开 | ✗ 用户无法断开 |

### 5.2 稳定性测试

- [ ] 长时间连接（24小时）无异常
- [ ] 文件传输大文件不中断
- [ ] 多次连接/断开无内存泄漏
- [ ] CM 进程崩溃不影响服务端

### 5.3 配置测试

**无人值守模式触发条件**：
```
approve-mode = "password"
verification-method = "use-permanent-password"
allow-hide-cm = "Y"
```

- [ ] 三个条件都满足 → 启动 --cm-no-ui
- [ ] 缺少任一条件 → 启动 --cm

## 6. 部署计划

### 6.1 版本兼容性

- ✓ 向后兼容：旧版本客户端无影响
- ✓ 配置兼容：使用现有配置项，无新增
- ✓ 协议兼容：不涉及协议修改

### 6.2 发布流程

1. 代码审查
2. 单元测试
3. 集成测试
4. Beta 测试（内部用户）
5. 正式发布

## 7. 风险评估

### 7.1 已知风险

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|---------|
| Linux headless 逻辑冲突 | 低 | 中 | 已处理，优先使用 headless 判断 |
| CM 进程启动失败 | 低 | 高 | 已有错误处理机制 |
| 配置项误判 | 低 | 中 | 严格条件判断（三个条件都要满足）|

### 7.2 回滚方案

如果出现问题，可以：
1. 回退到原版本
2. 临时禁用 `allow-hide-cm` 配置
3. 重启服务恢复默认行为

## 8. 后续优化

### 8.1 可选增强

1. **配置粒度优化**
   - 添加 `cm-mode` 配置项：`auto` / `ui` / `no-ui`
   - 允许用户显式选择模式

2. **日志增强**
   - 记录 CM 启动模式选择原因
   - 便于故障排查

3. **性能优化**
   - 无 UI 模式下减少不必要的消息传递
   - 优化 IPC 通道性能

## 9. 参考

- 原提交：`645fc82ef` - disable cm window on unattended access mode
- Linux headless 实现：`src/server/connection.rs:4400`
- CM no-ui 实现：`src/flutter.rs:1565`
- IPC 监听实现：`src/ui_cm_interface.rs:638`

## 10. 版本历史

| 版本 | 日期 | 作者 | 说明 |
|------|------|------|------|
| 1.0 | 2025-10-20 | Claude | 初始设计 |
