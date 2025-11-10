# 客户端频繁断开问题分析 - 提交 137ae8f0a8

## 问题描述

- **症状**: 使用 `--connect` 方式启动客户端连接远程桌面时，比较频繁断开
- **影响范围**: 修改版本客户端（官方版本无此问题）
- **相关提交**: 137ae8f0a8d9626c5bdac87655a493128fe96436

## 提交 137ae8f0a8 改动分析

### 提交信息
```
commit 137ae8f0a8d9626c5bdac87655a493128fe96436
Author: Gong Dewei <kylixs@qq.com>
Date:   Mon Oct 20 17:55:20 2025 +0800

    fix: unattended mode stability issues with cm-no-ui
```

### 改动文件
- `.docs/design/unattended-access-cm-no-ui.md` (新增设计文档)
- `Cargo.lock` (依赖更新)
- **`src/server/connection.rs`** (核心改动)

### 核心代码改动

**位置**: `src/server/connection.rs:4377-4417`

**改动内容**:

#### 改动前（原始代码）:
```rust
async fn start_ipc(...) -> ResultType<()> {
    // ...
    let mut args = vec!["--cm"];  // 始终使用 --cm

    #[cfg(target_os = "linux")]
    let mut user = None;

    // Linux headless 模式检测和用户设置
    #[cfg(target_os = "linux")]
    if crate::platform::is_headless_allowed() && linux_desktop_manager::is_headless() {
        // ... 设置用户
        args = vec!["--cm-no-ui"];  // 仅在 Linux headless 时使用 --cm-no-ui
    }

    // 启动 CM 进程
    // ...
}
```

#### 改动后（新代码）:
```rust
async fn start_ipc(...) -> ResultType<()> {
    // ...
    let mut args = vec!["--cm"];  // 默认使用 --cm

    #[cfg(target_os = "linux")]
    let mut user = None;

    // 新增：判断是否使用 --cm-no-ui
    // 优先级: 1. Linux headless  2. 无人值守模式  3. 默认 --cm
    let use_no_ui = {
        #[cfg(target_os = "linux")]
        {
            crate::platform::is_headless_allowed() && linux_desktop_manager::is_headless()
        }
        #[cfg(not(target_os = "linux"))]
        {
            false
        }
    } || hbb_common::password_security::hide_cm();  // ❌ 关键问题点

    if use_no_ui {
        args = vec!["--cm-no-ui"];
        log::info!("[CM] Starting connection manager in no-ui mode (unattended access or headless)");

        // Linux headless 用户设置（移到 if use_no_ui 内部）
        #[cfg(target_os = "linux")]
        if crate::platform::is_headless_allowed() && linux_desktop_manager::is_headless() {
            // ... 设置用户
        }
    }

    // 启动 CM 进程
    // ...
}
```

## 问题根源分析

### 1. `hide_cm()` 函数的作用域问题

**`hide_cm()` 定义** (`libs/hbb_common/src/password_security.rs:88`):

```rust
pub fn hide_cm() -> bool {
    approve_mode() == ApproveMode::Password
        && verification_method() == VerificationMethod::OnlyUsePermanentPassword
        && crate::config::option2bool("allow-hide-cm", &Config::get_option("allow-hide-cm"))
}
```

**问题**:
- `hide_cm()` 读取的是**全局配置**
- 配置存储在 `Config::get_option("approve-mode")` 等全局设置中
- **客户端和服务端共享同一个配置文件**

### 2. 客户端启动流程分析

#### 正常流程（官方版本）:

```
用户执行: rustdesk --connect <remote_id>
  ↓
core_main.rs 处理 --connect 参数
  ↓
启动 Flutter GUI 连接窗口
  ↓
用户输入密码/点击连接
  ↓
建立到远程服务端的连接
  ↓
远程服务端的 Connection 创建
  ↓
服务端调用 try_start_cm_ipc()
  ↓
服务端调用 start_ipc()
  ↓
检测是否需要启动 CM 进程:
  - 原版本：仅检查 Linux headless
  - **修改版本：检查 Linux headless || hide_cm()**  ← 问题所在
```

#### 问题场景：

**场景 A：客户端配置了无人值守模式**

如果用户在**客户端**机器上配置了无人值守访问（因为这台机器可能也作为服务端使用）：

```toml
# 客户端本地配置（C:\Users\xxx\AppData\Roaming\RustDesk\config\RustDesk2.toml）
approve-mode = "password"
verification-method = "use-permanent-password"
allow-hide-cm = "Y"
```

那么当这台机器作为**客户端**连接到其他服务端时：

1. **客户端进程**读取本地配置
2. `hide_cm()` 返回 `true`（因为本地配置了无人值守模式）
3. 但这是客户端在**连接别人**，不是被控端！
4. **这里不应该读取本地的无人值守配置**

### 3. 错误的判断逻辑

**问题代码**:
```rust
let use_no_ui = ... || hbb_common::password_security::hide_cm();
```

**问题分析**:

| 场景 | hide_cm() 返回值 | 期望行为 | 实际行为 | 结果 |
|------|-----------------|---------|---------|------|
| 客户端连接远程（客户端本地有无人值守配置） | `true` | 启动 `--cm`（显示窗口） | 启动 `--cm-no-ui` | ❌ **错误** |
| 客户端连接远程（客户端本地无无人值守配置） | `false` | 启动 `--cm` | 启动 `--cm` | ✅ 正确 |
| 服务端被连接（服务端有无人值守配置） | `true` | 启动 `--cm-no-ui` | 启动 `--cm-no-ui` | ✅ 正确 |
| 服务端被连接（服务端无无人值守配置） | `false` | 启动 `--cm` | 启动 `--cm` | ✅ 正确 |

### 4. `start_ipc()` 调用上下文

**关键发现**: `start_ipc()` 函数在 **服务端（被控端）** 被调用，而不是客户端！

查看调用链：
```rust
// src/server/connection.rs:2000-2010
fn try_start_cm_ipc(&mut self) {
    if let Some(p) = self.start_cm_ipc_para.take() {
        tokio::spawn(async move {
            if let Err(err) = start_ipc(
                p.rx_to_cm,
                p.tx_from_cm,
                p.rx_desktop_ready,
                p.tx_cm_stream_ready,
            ).await {
                // ...
            }
        });
    }
}
```

**重要理解**:
- `Connection` 结构体代表**被控端（服务端）**的一个连接
- 当客户端使用 `--connect` 连接到服务端时，是**服务端**创建 `Connection` 实例
- `start_ipc()` 在**服务端进程**中运行，启动服务端的 CM 进程

### 5. 实际问题推测

**问题可能不在客户端，而在服务端！**

#### 可能性 1：配置混淆

如果测试环境中：
- 服务端配置了无人值守模式（正确）
- 客户端也配置了无人值守模式（用于其他用途）
- 客户端连接到服务端时，服务端启动了 `--cm-no-ui` 而不是 `--cm`

这**应该**是正常的，但可能导致问题：

**`--cm` vs `--cm-no-ui` 的区别**:

| 特性 | --cm | --cm-no-ui |
|------|------|------------|
| UI 窗口 | ✅ 显示 | ❌ 不显示 |
| IPC 通信 | ✅ 支持 | ✅ 支持 |
| 用户交互 | ✅ 可以 | ❌ 不可以 |
| 资源占用 | 较高（GUI） | 较低（无GUI） |
| **稳定性** | ? | ? |

#### 可能性 2：`--cm-no-ui` 模式的稳定性问题

查看 Flutter 中 `--cm-no-ui` 的实现：

```rust
// src/flutter.rs 或相关文件
// --cm-no-ui 启动的是无界面的连接管理器
```

**潜在问题**:
1. `--cm-no-ui` 可能缺少某些初始化步骤
2. IPC 通道可能在某些情况下不稳定
3. 消息处理可能有遗漏

#### 可能性 3：条件判断时机问题

```rust
let use_no_ui = ... || hbb_common::password_security::hide_cm();
```

**问题**: `hide_cm()` 在 `start_ipc()` 调用时评估，此时：
- 连接可能还在建立中
- 配置可能还未完全加载
- 远程客户端的配置可能影响了判断

## 频繁断开的可能原因

### 原因 1：CM 进程启动模式不当

**场景**:
- 服务端应该使用 `--cm`（有 UI）
- 但因为错误的条件判断，使用了 `--cm-no-ui`
- 导致某些依赖 GUI 的功能失效，引起断开

### 原因 2：IPC 通道问题

**代码位置**: `src/server/connection.rs:4370`

```rust
if let Ok(s) = crate::ipc::connect(1000, "_cm").await {
    stream = Some(s);
} else {
    // 启动新的 CM 进程
}
```

**问题**:
- 如果 IPC 连接失败，会启动新的 CM 进程
- 如果启动的是错误的模式（`--cm-no-ui` vs `--cm`）
- 可能导致通信异常

### 原因 3：配置状态不一致

**问题**:
- `hide_cm()` 读取的是**当前进程**的配置
- 服务端进程可能继承了旧的配置
- 导致判断结果与预期不符

## 建议修复方案

### 方案 1：区分客户端和服务端上下文（推荐）

**问题**: `hide_cm()` 不应该影响客户端连接行为

**修复**:

```rust
// src/server/connection.rs:4377-4391

// 判断是否使用 --cm-no-ui
// 只在被控端（服务端）场景下检查 hide_cm()
let use_no_ui = {
    #[cfg(target_os = "linux")]
    {
        crate::platform::is_headless_allowed() && linux_desktop_manager::is_headless()
    }
    #[cfg(not(target_os = "linux"))]
    {
        // ✅ 修复：只在服务端模式下检查 hide_cm()
        // 客户端连接时，这段代码在服务端执行，应该检查
        // 但需要确保不是因为客户端的配置导致误判
        hbb_common::password_security::hide_cm()
    }
};
```

**注意**: 实际上这段代码**已经**在服务端运行，所以不是客户端配置的问题。

### 方案 2：添加调试日志（诊断用）

```rust
let use_no_ui = {
    #[cfg(target_os = "linux")]
    {
        crate::platform::is_headless_allowed() && linux_desktop_manager::is_headless()
    }
    #[cfg(not(target_os = "linux"))]
    {
        false
    }
} || hbb_common::password_security::hide_cm();

// ✅ 添加详细日志
log::info!(
    "[CM] CM mode decision: use_no_ui={}, hide_cm={}, approve_mode={:?}, verification_method={:?}, allow_hide_cm={}",
    use_no_ui,
    hbb_common::password_security::hide_cm(),
    hbb_common::password_security::approve_mode(),
    hbb_common::password_security::verification_method(),
    hbb_common::config::Config::get_option("allow-hide-cm")
);
```

### 方案 3：检查 `--cm-no-ui` 实现

**问题**: `--cm-no-ui` 可能有稳定性问题

**排查点**:
1. 查看 `flutter/lib/desktop/pages/connection_manager_no_ui.dart`（如果存在）
2. 检查 IPC 消息处理是否完整
3. 对比 `--cm` 和 `--cm-no-ui` 的实现差异

### 方案 4：回退测试

**临时方案**:

```rust
// 暂时禁用无人值守模式的 --cm-no-ui
let use_no_ui = {
    #[cfg(target_os = "linux")]
    {
        crate::platform::is_headless_allowed() && linux_desktop_manager::is_headless()
    }
    #[cfg(not(target_os = "linux"))]
    {
        false
    }
}; // 移除 || hbb_common::password_security::hide_cm()

// 或者添加开关
let use_no_ui = {
    #[cfg(target_os = "linux")]
    {
        crate::platform::is_headless_allowed() && linux_desktop_manager::is_headless()
    }
    #[cfg(not(target_os = "linux"))]
    {
        false
    }
} || (hbb_common::password_security::hide_cm() &&
      std::env::var("RUSTDESK_CM_NO_UI").is_ok()); // 仅在设置环境变量时启用
```

## 诊断步骤

### 步骤 1：确认问题范围

1. **确认客户端版本**:
   ```bash
   rustdesk --version
   ```

2. **确认服务端版本**:
   ```bash
   # 在服务端执行
   rustdesk --version
   ```

3. **检查是否使用了修改版本**:
   ```bash
   git log --oneline | grep 137ae8f0
   ```

### 步骤 2：检查配置

**客户端配置**:
```bash
# Windows
type "%APPDATA%\RustDesk\config\RustDesk2.toml"

# Linux
cat ~/.config/rustdesk/RustDesk2.toml
```

**服务端配置**:
```bash
# 同上
```

**检查项**:
- `approve-mode`
- `verification-method`
- `allow-hide-cm`

### 步骤 3：查看日志

**客户端日志**:
```bash
# Windows
type "%APPDATA%\RustDesk\RustDesk.log"

# Linux
cat ~/.config/rustdesk/RustDesk.log
```

**服务端日志**:
- 查找 `[CM] Starting connection manager` 相关日志
- 确认使用的是 `--cm` 还是 `--cm-no-ui`

**关键日志搜索**:
```bash
grep "\[CM\]" RustDesk.log
grep "start_ipc" RustDesk.log
grep "cm-no-ui" RustDesk.log
```

### 步骤 4：进程检查

使用刚才创建的脚本检查服务端的进程树：

```powershell
# Windows
.\scripts\check-port.ps1 21118
```

**检查输出**:
- 确认 CM 子进程使用的参数是 `--cm` 还是 `--cm-no-ui`
- 查看进程层级树

### 步骤 5：抓包分析（如果需要）

```bash
# 在服务端或客户端抓包
tcpdump -i any -w rustdesk.pcap port 21118 or port 21119
```

## 总结

### 根本问题

**提交 137ae8f0a8 的改动**在服务端引入了基于 `hide_cm()` 的 CM 模式选择逻辑：

```rust
let use_no_ui = (linux_headless) || hide_cm();
```

**可能的问题**:

1. ✅ **逻辑本身是正确的**：这段代码在服务端运行，读取的是服务端配置
2. ❌ **潜在问题**：`--cm-no-ui` 模式可能存在稳定性问题
3. ❌ **时机问题**：配置读取时机可能不对
4. ❌ **环境差异**：修改版本和官方版本的 `--cm-no-ui` 实现可能有差异

### 下一步行动

1. **立即诊断**：使用步骤 2-4 检查实际运行情况
2. **添加日志**：应用方案 2 添加详细日志
3. **对比测试**：
   - 使用官方版本客户端连接修改版本服务端
   - 使用修改版本客户端连接官方版本服务端
   - 确定问题在客户端还是服务端
4. **临时修复**：如果确认是 `--cm-no-ui` 问题，应用方案 4 临时禁用

### 优先级建议

| 优先级 | 行动 | 原因 |
|-------|------|------|
| P0 | 确认服务端是否使用了 `--cm-no-ui` | 定位问题源头 |
| P0 | 检查服务端配置（hide_cm 相关） | 确认条件是否满足 |
| P1 | 添加详细日志并重现问题 | 收集诊断信息 |
| P1 | 对比官方版本行为 | 验证假设 |
| P2 | 检查 `--cm-no-ui` 实现差异 | 找到根本原因 |
| P3 | 考虑回退或添加开关 | 临时规避方案 |
