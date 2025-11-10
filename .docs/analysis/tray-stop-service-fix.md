# Windows Tray "停止服务" 修复总结

## 修复内容

已修复 Windows 系统托盘点击"停止服务"会删除服务的问题。

## 修改的文件

### 1. `src/platform/windows.rs` (新增 2 个函数)

**位置**：第 2645-2683 行

**新增函数 1**：`stop_service()` - 停止服务但不删除

```rust
/// Stop the RustDesk service without uninstalling it
/// This is called from the system tray when user clicks "Stop service"
pub fn stop_service() -> bool {
    log::info!("Stopping service...");
    let app_name = crate::get_app_name();
    let cmds = format!(
        "
    chcp 65001
    sc stop {app_name}
    "
    );
    if let Err(err) = run_cmds(cmds, false, "stop_service") {
        log::error!("Failed to stop service: {}", err);
        return false;
    }
    Config::set_option("stop-service".into(), "Y".into());
    log::info!("Service stopped successfully");
    true
}
```

**新增函数 2**：`start_service()` - 启动已停止的服务

```rust
/// Start the RustDesk service
/// This is called from the system tray when user clicks "Start service"
pub fn start_service() -> bool {
    log::info!("Starting service...");
    let app_name = crate::get_app_name();
    let cmds = format!(
        "
    chcp 65001
    sc start {app_name}
    "
    );
    if let Err(err) = run_cmds(cmds, false, "start_service") {
        log::error!("Failed to start service: {}", err);
        return false;
    }
    Config::set_option("stop-service".into(), "".into());
    log::info!("Service started successfully");
    true
}
```

### 2. `src/tray.rs` (修改菜单处理逻辑)

**位置**：第 158-177 行

**修改前**：
```rust
if event.id == quit_i.id() {
    if !crate::platform::uninstall_service(false, false) {
        *control_flow = ControlFlow::Exit;
    }
}
```

**修改后**：
```rust
if event.id == quit_i.id() {
    // Stop the service without uninstalling it
    // The tray process will continue running
    #[cfg(windows)]
    {
        if !crate::platform::stop_service() {
            log::error!("Failed to stop service");
        }
    }
    #[cfg(not(windows))]
    {
        if !crate::platform::uninstall_service(false, false) {
            *control_flow = ControlFlow::Exit;
        }
    }
}
```

## 修复效果

### 修复前的行为

点击"停止服务"时会：
1. ❌ 停止服务
2. ❌ **删除服务** (sc delete)
3. ❌ 删除开机启动项
4. ❌ 强制结束所有进程
5. ❌ 退出 Tray 程序

**后果**：用户需要重新运行 `--install-service` 才能恢复服务。

### 修复后的行为

点击"停止服务"时会：
1. ✅ 停止服务 (sc stop)
2. ✅ 保留服务注册信息（不删除）
3. ✅ 保留开机启动项
4. ✅ Tray 程序继续运行
5. ✅ 用户可以使用 `sc start rustdesk` 或命令重新启动

**优势**：
- 不会误删除服务
- Tray 继续运行，可以查看状态
- 服务可以随时重新启动

## 技术细节

### `stop_service` vs `uninstall_service`

| 操作 | stop_service | uninstall_service |
|------|--------------|-------------------|
| 停止服务 | ✅ | ✅ |
| 删除服务 | ❌ | ✅ |
| 删除启动项 | ❌ | ✅ |
| 结束进程 | ❌ | ✅ |
| 退出程序 | ❌ | ✅ |
| 保留配置 | ✅ | ❌ |

### 函数返回值

- `true` - 操作成功
- `false` - 操作失败（记录错误日志）

### 平台兼容性

- **Windows**: 使用新的 `stop_service()` 函数
- **Linux/macOS**: 保持原有的 `uninstall_service()` 行为（需要后续优化）

## 测试建议

### 测试场景 1：停止服务

1. 启动 RustDesk Tray：`rustdesk --tray`
2. 右键点击系统托盘图标
3. 点击"停止服务"
4. 验证：
   ```powershell
   # 验证服务已停止但未删除
   sc query rustdesk
   # 预期：STATE = STOPPED

   # 验证服务仍然注册
   sc qc rustdesk
   # 预期：显示服务配置信息

   # 验证 Tray 进程仍在运行
   Get-Process | Where-Object {$_.ProcessName -like "*rustdesk*"}
   # 预期：rustdesk.exe (tray) 仍在运行
   ```

### 测试场景 2：重新启动服务

```powershell
# 方法 1：使用 sc 命令
sc start rustdesk

# 方法 2：使用 RustDesk 命令
rustdesk --start-service

# 验证服务已启动
sc query rustdesk
# 预期：STATE = RUNNING
```

### 测试场景 3：卸载服务（对比）

```powershell
# 使用卸载命令
rustdesk --uninstall-service

# 验证服务已删除
sc query rustdesk
# 预期：错误 - 指定的服务不存在
```

## 后续优化建议

### 1. 添加"启动服务"菜单项

在 Tray 菜单中添加"启动服务"选项，根据服务状态动态显示：
- 服务运行中：显示"停止服务"
- 服务已停止：显示"启动服务"

**实现**：
```rust
// 动态检查服务状态
let service_running = crate::platform::is_service_running();
let action_item = if service_running {
    MenuItem::new(translate("Stop service".to_owned()), true, None)
} else {
    MenuItem::new(translate("Start service".to_owned()), true, None)
};
```

### 2. Linux/macOS 平台优化

为 Linux 和 macOS 也实现类似的 `stop_service` 功能，而不是直接卸载服务。

### 3. 添加服务状态指示

在 Tray tooltip 中显示服务状态：
- "RustDesk - 服务运行中"
- "RustDesk - 服务已停止"

### 4. 添加错误提示

当停止/启动服务失败时，显示友好的错误提示（Toast 通知）。

## 相关文件

- [问题分析文档](./tray-stop-service-issue.md)
- `src/platform/windows.rs` - Windows 平台实现
- `src/tray.rs` - 系统托盘实现

## 修复日期

2025-10-20

## 构建状态

正在构建...

编译完成后需要测试验证修复效果。
