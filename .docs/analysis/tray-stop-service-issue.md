# Windows Tray "停止服务" 问题分析

## 问题描述

用户反馈：点击 Windows 系统托盘图标的"停止服务"菜单项后，服务被删除了，而不是简单地停止。

## 根本原因

### 问题代码位置

**文件**：`src/tray.rs:159-168`

```rust
if let Ok(event) = menu_channel.try_recv() {
    if event.id == quit_i.id() {
        // quit_i 是 "Stop service" 菜单项
        if !crate::platform::uninstall_service(false, false) {
            *control_flow = ControlFlow::Exit;
        }
    }
}
```

**问题**：点击"停止服务"时，调用的是 `uninstall_service()` 而不是 `stop_service()`！

### `uninstall_service` 的行为

**文件**：`src/platform/windows.rs:2620-2643`

```rust
pub fn uninstall_service(show_new_window: bool, _: bool) -> bool {
    log::info!("Uninstalling service...");
    Config::set_option("stop-service".into(), "Y".into());
    let cmds = format!(
        "
    chcp 65001
    sc stop {app_name}        ← 停止服务
    sc delete {app_name}      ← ❌ 删除服务（问题所在）
    if exist ... del ...      ← 删除开机启动快捷方式
    taskkill /F /IM {broker_exe}
    taskkill /F /IM {app_name}.exe{filter}
    ",
        app_name = crate::get_app_name(),
        broker_exe = WIN_TOPMOST_INJECTED_PROCESS_EXE,
    );
    run_cmds(cmds, false, "uninstall");
    run_after_run_cmds(!show_new_window);
    std::process::exit(0);
}
```

**执行的操作**：
1. ✅ 停止服务 (`sc stop`)
2. ❌ **删除服务** (`sc delete`) - 不应该
3. ❌ 删除开机启动项 - 不应该
4. ❌ 强制结束所有相关进程 - 不应该
5. ❌ 退出当前程序 - 不应该

## 期望行为

点击"停止服务"应该：
1. ✅ 停止 Windows 服务
2. ✅ 保留服务的注册信息（不删除）
3. ✅ 保留开机启动项
4. ✅ 保留 Tray 进程运行
5. ✅ 用户可以再次点击"启动服务"来恢复

## 修复方案

### 方案 A：创建独立的 `stop_service` 函数（推荐）

**步骤 1**：在 `src/platform/windows.rs` 添加 `stop_service` 函数

```rust
/// Stop the RustDesk service without uninstalling it
pub fn stop_service() -> bool {
    log::info!("Stopping service...");
    let app_name = crate::get_app_name();
    let cmds = format!(
        "
    chcp 65001
    sc stop {app_name}
    ",
    );
    if let Err(err) = run_cmds(cmds, false, "stop_service") {
        log::error!("Failed to stop service: {}", err);
        return false;
    }
    true
}
```

**步骤 2**：在 `src/platform/mod.rs` 导出函数

```rust
#[cfg(windows)]
pub use windows::stop_service;
```

**步骤 3**：修改 `src/tray.rs:159-168`

```rust
if let Ok(event) = menu_channel.try_recv() {
    if event.id == quit_i.id() {
        // 调用 stop_service 而不是 uninstall_service
        if !crate::platform::stop_service() {
            log::error!("Failed to stop service");
        }
        // 不退出 tray 进程，保持运行
    } else if event.id == open_i.id() {
        open_func();
    }
}
```

**步骤 4**：添加"启动服务"菜单项

修改 `src/tray.rs:62-65` 添加"启动服务"菜单项：

```rust
let tray_menu = Menu::new();
let stop_i = MenuItem::new(translate("Stop service".to_owned()), true, None);
let start_i = MenuItem::new(translate("Start service".to_owned()), true, None);
let open_i = MenuItem::new(translate("Open".to_owned()), true, None);
tray_menu.append_items(&[&open_i, &start_i, &stop_i]).ok();
```

并在事件处理中添加启动服务的逻辑：

```rust
if event.id == stop_i.id() {
    if !crate::platform::stop_service() {
        log::error!("Failed to stop service");
    }
} else if event.id == start_i.id() {
    if !crate::platform::start_service() {
        log::error!("Failed to start service");
    }
}
```

### 方案 B：修改 `uninstall_service` 增加参数

在 `uninstall_service` 增加参数控制是否删除服务：

```rust
pub fn uninstall_service(show_new_window: bool, delete_service: bool) -> bool {
    log::info!("Stopping service...");
    let cmds = if delete_service {
        format!(
            "
        sc stop {app_name}
        sc delete {app_name}
        if exist ... del ...
        taskkill ...
        ",
        )
    } else {
        format!(
            "
        sc stop {app_name}
        ",
        )
    };
    // ...
}
```

然后在 tray.rs 中调用：
```rust
crate::platform::uninstall_service(false, false) // false 表示不删除服务
```

**缺点**：
- 函数名称不准确（uninstall_service 实际可能不 uninstall）
- 代码逻辑混乱

### 方案 C：使用配置选项判断

检查是否需要删除服务，基于用户意图或配置。

**缺点**：
- 增加复杂度
- 用户体验不明确

## 推荐方案

**采用方案 A**：创建独立的 `stop_service` 和 `start_service` 函数

**理由**：
1. ✅ 代码清晰，功能明确
2. ✅ 符合用户期望（停止 ≠ 卸载）
3. ✅ 可以添加"启动服务"功能
4. ✅ 不影响现有的卸载逻辑

## 实施细节

### 需要添加的函数

#### 1. `stop_service` - 停止服务

```rust
pub fn stop_service() -> bool {
    log::info!("Stopping service...");
    let app_name = crate::get_app_name();
    let cmds = format!("sc stop {app_name}");
    if let Err(err) = run_cmds(cmds, false, "stop_service") {
        log::error!("Failed to stop service: {}", err);
        return false;
    }
    Config::set_option("stop-service".into(), "Y".into());
    true
}
```

#### 2. `start_service` - 启动服务

```rust
pub fn start_service() -> bool {
    log::info!("Starting service...");
    let app_name = crate::get_app_name();
    let cmds = format!("sc start {app_name}");
    if let Err(err) = run_cmds(cmds, false, "start_service") {
        log::error!("Failed to start service: {}", err);
        return false;
    }
    Config::set_option("stop-service".into(), "".into());
    true
}
```

#### 3. `is_service_running` - 检查服务状态

```rust
pub fn is_service_running() -> bool {
    // 检查服务状态
    // 可以用于动态更新菜单项（显示"启动"或"停止"）
    is_service_running_w(&get_service_name())
}
```

### 需要修改的翻译

在所有语言文件中添加：
- "Start service" → "启动服务"
- "Service stopped" → "服务已停止"
- "Service started" → "服务已启动"

### 菜单动态更新

根据服务状态动态显示菜单项：
- 服务运行中：显示"停止服务"
- 服务已停止：显示"启动服务"

## 测试建议

1. **停止服务测试**：
   - 点击"停止服务"
   - 验证服务已停止：`sc query rustdesk`
   - 验证服务未删除：服务仍在服务列表中
   - 验证 Tray 进程仍在运行

2. **启动服务测试**：
   - 点击"启动服务"
   - 验证服务已启动：`sc query rustdesk`
   - 验证可以接受远程连接

3. **卸载测试**：
   - 使用 `--uninstall-service` 命令
   - 验证服务被删除：`sc query rustdesk` 返回错误

## 相关问题

### 为什么会有这个问题？

可能的原因：
1. 代码复用不当（停止服务复用了卸载服务的代码）
2. 功能需求不清晰（停止 vs 卸载）
3. 缺少独立的停止服务功能

### 其他平台

需要检查 Linux 和 macOS 平台是否有类似问题：
- `src/platform/linux.rs`
- `src/platform/macos.rs`

## 优先级

**高**：这是一个严重的用户体验问题

用户只想临时停止服务，结果服务被删除了，需要重新安装服务才能恢复。

## 总结

**问题**：点击"停止服务"会删除服务

**原因**：错误地调用了 `uninstall_service` 而不是 `stop_service`

**修复**：创建独立的 `stop_service` 和 `start_service` 函数

**影响**：Windows 平台的 Tray 功能
