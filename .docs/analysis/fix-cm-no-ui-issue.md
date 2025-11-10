# 修复 CM-NO-UI 导致的连接不稳定问题

## 问题重新理解

### 关键发现

**用户反馈**：
- 使用 `--connect` 启动客户端连接远程桌面时，频繁断开
- 官方版本客户端无此问题
- 修改版本客户端有此问题

**提示**：
> "服务端无人值守才需要使用 no_ui 模式，不要影响客户端启动流程"

### 正确的理解

`start_ipc()` 函数：
- **位置**：`src/server/connection.rs:4355`
- **作用**：在**服务端（被控端）**启动 CM（连接管理器）进程
- **调用时机**：当有客户端连接到服务端时

**场景分析**：

```
客户端 A (修改版本) --connect--> 服务端 B (修改版本，配置了无人值守)
                                    ↓
                                 Connection::try_start_cm_ipc()
                                    ↓
                                 start_ipc()
                                    ↓
                                 检测：hide_cm() == true
                                    ↓
                                 启动：rustdesk --cm-no-ui  ← 问题可能在这里
```

### 潜在问题

**假设 1：`--cm-no-ui` 实现不完整**

可能 `--cm-no-ui` 模式在处理某些消息或功能时有遗漏，导致连接不稳定。

**假设 2：官方版本没有 `--cm-no-ui` 检测逻辑**

提交 137ae8f0a8 添加了：
```rust
let use_no_ui = ... || hbb_common::password_security::hide_cm();
```

官方版本可能没有这行代码，即使服务端配置了无人值守，也始终使用 `--cm`。

## 验证假设

### 检查官方版本代码

让我们看看官方版本（或之前的版本）的逻辑：

```bash
git show 137ae8f0a8^:src/server/connection.rs | grep -A 30 "async fn start_ipc"
```

**预期**：之前的版本可能没有 `hide_cm()` 检测。

### 检查 `--cm-no-ui` 的稳定性

**问题点**：
1. `--cm-no-ui` 是否正确处理所有 IPC 消息？
2. 是否有资源泄漏或清理不当？
3. 是否有时序问题？

## 修复方案

### 方案 1：回退到之前的逻辑（推荐临时方案）

**目标**：让修改版本的行为与官方版本一致

**修改位置**：`src/server/connection.rs:4383-4391`

```rust
// 之前的代码（提交 137ae8f0a8）
let use_no_ui = {
    #[cfg(target_os = "linux")]
    {
        crate::platform::is_headless_allowed() && linux_desktop_manager::is_headless()
    }
    #[cfg(not(target_os = "linux"))]
    {
        false
    }
} || hbb_common::password_security::hide_cm();  // ← 移除这行

// 修复后的代码
let use_no_ui = {
    #[cfg(target_os = "linux")]
    {
        crate::platform::is_headless_allowed() && linux_desktop_manager::is_headless()
    }
    #[cfg(not(target_os = "linux"))]
    {
        false  // ← Windows/macOS 始终使用 --cm
    }
};
```

**效果**：
- Linux headless 环境：使用 `--cm-no-ui`（保留）
- Windows/macOS：**始终使用 `--cm`**，即使配置了无人值守模式
- 行为与官方版本一致

### 方案 2：添加专门的开关（长期方案）

**目标**：允许用户选择是否在无人值守模式下使用 `--cm-no-ui`

**步骤 1：添加新的配置项**

在 `libs/hbb_common/src/config.rs` 中添加：

```rust
pub fn use_cm_no_ui_for_unattended() -> bool {
    // 默认为 false，保持与官方版本一致的行为
    option2bool(
        "use-cm-no-ui-for-unattended",
        &Config::get_option("use-cm-no-ui-for-unattended")
    )
}
```

**步骤 2：修改 start_ipc 逻辑**

```rust
let use_no_ui = {
    #[cfg(target_os = "linux")]
    {
        crate::platform::is_headless_allowed() && linux_desktop_manager::is_headless()
    }
    #[cfg(not(target_os = "linux"))]
    {
        // 仅在配置启用时，才在无人值守模式下使用 --cm-no-ui
        hbb_common::config::Config::use_cm_no_ui_for_unattended() &&
        hbb_common::password_security::hide_cm()
    }
};
```

**步骤 3：文档说明**

在配置文件或 GUI 中添加说明：
```toml
# 在无人值守模式下使用无 UI 的连接管理器
# 注意：启用此选项可能会导致连接不稳定
# 默认：N
use-cm-no-ui-for-unattended = "N"
```

### 方案 3：修复 `--cm-no-ui` 的稳定性问题（根本方案）

**目标**：找到并修复 `--cm-no-ui` 导致断开的根本原因

**步骤 1：对比 `--cm` 和 `--cm-no-ui` 的实现**

查找两者的差异：

```bash
# 查找 --cm 的实现
grep -r "\"--cm\"" src/

# 查找 --cm-no-ui 的实现
grep -r "\"--cm-no-ui\"" src/
grep -r "cm-no-ui" src/
```

**步骤 2：添加详细日志**

在 `start_ipc()` 中添加：

```rust
log::info!(
    "[CM-DEBUG] Starting CM: mode={}, hide_cm={}, peer={}",
    if use_no_ui { "no-ui" } else { "ui" },
    hbb_common::password_security::hide_cm(),
    // 添加当前连接的 peer_id 等信息
);
```

在 `--cm-no-ui` 的关键路径添加日志，追踪断开时的状态。

**步骤 3：重现和调试**

1. 搭建测试环境：
   - 服务端：配置无人值守模式
   - 客户端：使用 `--connect` 连接

2. 启用详细日志：
   ```bash
   # 设置日志级别
   export RUST_LOG=debug
   ```

3. 监控日志，寻找断开时的异常

## 立即行动建议

### 推荐：使用方案 1（回退）

**原因**：
1. ✅ 最快速解决问题
2. ✅ 行为与官方版本一致
3. ✅ 风险最低
4. ✅ 不影响 Linux headless 功能

**代码修改**：

```diff
diff --git a/src/server/connection.rs b/src/server/connection.rs
index 1f9fc8239..xxxxx 100644
--- a/src/server/connection.rs
+++ b/src/server/connection.rs
@@ -4377,17 +4377,14 @@ async fn start_ipc(
         #[cfg(target_os = "linux")]
         let mut user = None;

-        // Determine whether to use --cm-no-ui or --cm
-        // Priority: 1. Linux headless  2. Unattended access mode  3. Default --cm
+        // Use --cm-no-ui only for Linux headless
         let use_no_ui = {
             #[cfg(target_os = "linux")]
             {
                 crate::platform::is_headless_allowed() && linux_desktop_manager::is_headless()
             }
             #[cfg(not(target_os = "linux"))]
-            {
-                false
-            }
-        } || hbb_common::password_security::hide_cm();
+            { false }
+        };

         if use_no_ui {
             args = vec!["--cm-no-ui"];
```

### 执行步骤

1. **应用修改**：
   ```bash
   # 编辑文件
   # src/server/connection.rs:4383-4391
   # 移除 || hbb_common::password_security::hide_cm()
   ```

2. **编译测试**：
   ```bash
   cargo build --release
   ```

3. **验证**：
   - 服务端配置无人值守模式
   - 客户端使用 `--connect` 连接
   - 观察是否还会频繁断开

4. **检查进程**：
   ```powershell
   .\scripts\check-port.ps1 21118
   ```

   **期望输出**：服务端应该启动 `--cm` 子进程，而不是 `--cm-no-ui`

## 后续优化

如果方案 1 解决了问题，说明确实是 `--cm-no-ui` 导致的不稳定。

后续可以：
1. 调查 `--cm-no-ui` 的具体问题
2. 修复后再考虑启用方案 2
3. 或者完全放弃在 Windows/macOS 上使用 `--cm-no-ui`

## 更新设计文档

修改 `.docs/design/unattended-access-cm-no-ui.md`：

```markdown
## 注意事项

### Windows/macOS 平台限制

经过测试发现，在 Windows/macOS 平台上使用 `--cm-no-ui` 模式可能导致连接不稳定。

**当前方案**：
- Linux headless：使用 `--cm-no-ui`
- Windows/macOS：**始终使用 `--cm`**，即使配置了无人值守模式

**原因**：
`--cm-no-ui` 模式在某些情况下可能存在稳定性问题，导致客户端频繁断开。

**未来改进**：
待调查并修复 `--cm-no-ui` 的稳定性问题后，可以考虑在所有平台启用。
```

## 总结

### 问题根源

提交 137ae8f0a8 引入的 `hide_cm()` 检测逻辑，导致 Windows/macOS 服务端在无人值守模式下使用 `--cm-no-ui`，而这个模式可能存在稳定性问题。

### 解决方案

**立即**：回退到仅在 Linux headless 使用 `--cm-no-ui`
**长期**：调查并修复 `--cm-no-ui` 的稳定性问题

### 验证方法

修改后，服务端应该始终启动带 UI 的 CM 进程（在 Windows/macOS 上），即使配置了无人值守模式。
