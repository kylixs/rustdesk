# CM子进程可执行文件路径权限问题

## 问题描述

**核心问题**：cm子进程虽然以登录用户身份运行，但使用的可执行文件路径位于 systemprofile 目录，登录用户可能无权限访问，导致启动失败或连接自动断开。

## 问题根源分析

### 1. 服务进程解压位置

**自解压服务进程（SYSTEM用户）**解压可执行文件到：
```
C:\Windows\system32\config\systemprofile\AppData\Local\rustdesk\<version>\rustdesk.exe
```

### 2. CM子进程启动路径

**代码路径**: `src/server/connection.rs:4407`
```rust
res = crate::platform::run_as_user(args.clone());
```

**实现**: `src/platform/windows.rs:800-801`
```rust
pub fn run_as_user(arg: Vec<&str>) -> ResultType<Option<std::process::Child>> {
    run_exe_in_cur_session(std::env::current_exe()?.to_str().unwrap_or(""), arg, false)
}
```

**关键问题**：使用 `std::env::current_exe()` 获取可执行文件路径
- 返回**当前进程**的可执行文件路径
- 如果服务进程在 systemprofile，返回的就是 systemprofile 中的路径
- 即：`C:\Windows\system32\config\systemprofile\AppData\Local\rustdesk\<version>\rustdesk.exe`

### 3. 权限冲突

**问题流程**：
```
1. SYSTEM 用户服务进程
   └─ 解压到: C:\Windows\system32\config\systemprofile\...\rustdesk.exe

2. 调用 run_as_user 启动 cm 子进程
   └─ 可执行文件路径: C:\Windows\system32\config\systemprofile\...\rustdesk.exe
   └─ 运行身份: 登录用户 (gongdewei)

3. 权限检查
   └─ 登录用户尝试访问: systemprofile\...\rustdesk.exe
   └─ 结果: 可能无权限访问 ❌
```

**systemprofile 目录的 ACL**：
- Owner: `NT AUTHORITY\SYSTEM`
- Full Control: `SYSTEM`, `Administrators`
- **普通登录用户**: 可能无访问权限

## 测试验证

使用权限检查脚本测试：
```powershell
powershell -ExecutionPolicy Bypass -File scripts/check-dir-permissions.ps1 -Path "C:\Windows\system32\config\systemprofile\AppData\Local\rustdesk\1.4.3-jlc18"
```

**可能结果**：
- 管理员账户：可能有访问权限
- 普通用户账户：可能无访问权限 ⚠️

## 解决方案

### 方案1：复制到用户可访问的共享目录 ✅ 推荐

**原理**：将可执行文件复制到所有用户都可访问的目录，如 `C:\ProgramData`

**实现步骤**：

1. **获取目标目录**（使用现有函数）：
   ```rust
   // src/platform/windows.rs:2574
   pub fn user_accessible_folder() -> ResultType<PathBuf> {
       let disk = std::env::var("SystemDrive").unwrap_or("C:".to_string());
       let dir1 = PathBuf::from(format!("{}\\ProgramData", disk));
       let dir2 = PathBuf::from(format!("{}\\Windows\\Temp", disk));
       // ...
       Ok(dir)  // 返回 C:\ProgramData 或 C:\Windows\Temp
   }
   ```

2. **复制可执行文件并启动cm子进程**：
   ```rust
   // 在 src/server/connection.rs 的 run_as_user 调用前

   #[cfg(target_os = "windows")]
   fn get_user_accessible_exe() -> ResultType<String> {
       let current_exe = std::env::current_exe()?;
       let current_exe_str = current_exe.to_string_lossy().to_string();

       // 如果当前路径已经在用户可访问目录，直接返回
       if current_exe_str.contains("\\ProgramData\\") ||
          current_exe_str.contains("\\Temp\\") {
           return Ok(current_exe_str);
       }

       // 构建目标路径
       let target_dir = crate::platform::user_accessible_folder()?
           .join(&*hbb_common::config::APP_NAME.read().unwrap())
           .join(crate::VERSION);

       std::fs::create_dir_all(&target_dir)?;
       crate::platform::set_path_permission(&target_dir, "F").ok();

       let target_exe = target_dir.join(current_exe.file_name().unwrap());

       // 如果目标文件不存在或版本不同，复制
       if !target_exe.exists() ||
          needs_update(&current_exe, &target_exe)? {
           std::fs::copy(&current_exe, &target_exe)?;
           crate::platform::set_path_permission(&target_exe, "RX").ok();
           log::info!("[CM] Copied executable to user-accessible location: {:?}", target_exe);
       }

       Ok(target_exe.to_string_lossy().to_string())
   }

   fn needs_update(src: &Path, dst: &Path) -> ResultType<bool> {
       let src_meta = std::fs::metadata(src)?;
       let dst_meta = std::fs::metadata(dst)?;
       // 比较文件大小和修改时间
       Ok(src_meta.len() != dst_meta.len() ||
          src_meta.modified()? != dst_meta.modified()?)
   }
   ```

3. **修改 run_as_user 调用**：
   ```rust
   // src/server/connection.rs
   #[cfg(target_os = "windows")]
   {
       // 获取用户可访问的可执行文件路径
       let exe_path = match get_user_accessible_exe() {
           Ok(path) => path,
           Err(e) => {
               log::error!("[CM] Failed to get user-accessible exe: {:?}, using current exe", e);
               std::env::current_exe()?.to_string_lossy().to_string()
           }
       };
       log::info!("[CM] Starting cm subprocess with exe: {}, args: {:?}", exe_path, args);
       res = crate::platform::run_exe_as_user(&exe_path, args.clone());
   }

   #[cfg(not(target_os = "windows"))]
   {
       log::info!("[CM] Starting cm subprocess with args: {:?}", args);
       res = crate::platform::run_as_user(args.clone());
   }
   ```

4. **添加新函数**：
   ```rust
   // src/platform/windows.rs
   pub fn run_exe_as_user(exe: &str, arg: Vec<&str>) -> ResultType<Option<std::process::Child>> {
       run_exe_in_cur_session(exe, arg, false)
   }
   ```

**优点**：
- ✅ 所有用户都可以访问 `C:\ProgramData`
- ✅ 不依赖特定用户目录
- ✅ 支持多用户场景
- ✅ 只需复制一次，所有用户共享
- ✅ 有现成的 `user_accessible_folder()` 函数

**缺点**：
- ⚠️ 需要额外磁盘空间（每个版本约 30-50MB）
- ⚠️ 需要管理文件版本更新

**目标路径示例**：
```
C:\ProgramData\RustDesk\1.4.3-jlc18\rustdesk.exe
```

### 方案2：复制到登录用户目录

**原理**：复制可执行文件到登录用户的 AppData 目录

**实现参考**：已有类似实现在 `portable_service.rs:596-616`
```rust
match hbb_common::directories_next::UserDirs::new() {
    Some(user_dir) => {
        let dir = user_dir
            .home_dir()
            .join("AppData")
            .join("Local")
            .join("rustdesk-sciter");  // 改为 rustdesk-cm
        if std::fs::create_dir_all(&dir).is_ok() {
            let dst = dir.join("rustdesk.exe");
            if std::fs::copy(&exe, &dst).is_ok() {
                if dst.exists() {
                    if set_path_permission(&dir, "RX").is_ok() {
                        exe = dst.to_string_lossy().to_string();
                    }
                }
            }
        }
    }
    None => {}
}
```

**修改为**：
```rust
fn get_user_local_exe() -> ResultType<String> {
    let current_exe = std::env::current_exe()?;

    // 获取登录用户的home目录
    let user_home = crate::platform::get_active_user_home()
        .ok_or_else(|| anyhow!("Failed to get active user home"))?;

    let target_dir = user_home
        .join("AppData")
        .join("Local")
        .join(&*hbb_common::config::APP_NAME.read().unwrap())
        .join(crate::VERSION);

    std::fs::create_dir_all(&target_dir)?;
    crate::platform::set_path_permission(&target_dir, "F").ok();

    let target_exe = target_dir.join(current_exe.file_name().unwrap());

    if !target_exe.exists() {
        std::fs::copy(&current_exe, &target_exe)?;
        crate::platform::set_path_permission(&target_exe, "RX").ok();
        log::info!("[CM] Copied executable to user directory: {:?}", target_exe);
    }

    Ok(target_exe.to_string_lossy().to_string())
}
```

**优点**：
- ✅ 完全在用户目录，权限明确
- ✅ 不同用户使用各自的副本

**缺点**：
- ❌ 多用户时需要多次复制（浪费空间）
- ❌ 需要获取登录用户信息
- ❌ RDP多用户场景复杂

**目标路径示例**：
```
C:\Users\gongdewei\AppData\Local\RustDesk\1.4.3-jlc18\rustdesk.exe
```

### 方案3：修改 systemprofile 目录权限 ⚠️ 不推荐

**原理**：给 systemprofile 目录添加 Users 组的读取和执行权限

```powershell
icacls "C:\Windows\system32\config\systemprofile\AppData\Local\rustdesk" /grant Users:RX /T
```

**优点**：
- ✅ 简单，不需要复制文件

**缺点**：
- ❌ 修改系统关键目录权限，有安全风险
- ❌ 可能被系统更新恢复
- ❌ 不符合最小权限原则
- ❌ **强烈不推荐**

## 推荐实施方案

**采用方案1：复制到 C:\ProgramData**

### 实施步骤

1. **在 src/server/connection.rs 添加**：
   ```rust
   #[cfg(target_os = "windows")]
   fn get_user_accessible_exe() -> ResultType<String> {
       // 实现如上方案1
   }
   ```

2. **修改 cm 启动逻辑**：
   ```rust
   // 在 connection.rs:4406 附近
   #[cfg(target_os = "windows")]
   let exe_path = get_user_accessible_exe().unwrap_or_else(|e| {
       log::error!("[CM] Failed to get user-accessible exe: {:?}", e);
       std::env::current_exe()
           .unwrap()
           .to_string_lossy()
           .to_string()
   });

   #[cfg(not(target_os = "windows"))]
   let exe_path = std::env::current_exe()
       .unwrap()
       .to_string_lossy()
       .to_string();

   log::info!("[CM] Using executable: {}", exe_path);
   ```

3. **添加 Windows 平台函数**：
   ```rust
   // src/platform/windows.rs
   pub fn run_exe_as_user(exe: &str, arg: Vec<&str>) -> ResultType<Option<std::process::Child>> {
       run_exe_in_cur_session(exe, arg, false)
   }
   ```

4. **调用新函数**：
   ```rust
   #[cfg(target_os = "windows")]
   {
       res = crate::platform::run_exe_as_user(&exe_path, args.clone());
   }
   #[cfg(not(target_os = "windows"))]
   {
       res = crate::platform::run_as_user(args.clone());
   }
   ```

## 测试验证

### 1. 权限验证
```powershell
# 检查 ProgramData 目录权限
powershell -ExecutionPolicy Bypass -File scripts/check-dir-permissions.ps1 -Path "C:\ProgramData\RustDesk"

# 检查 systemprofile 目录权限（对比）
powershell -ExecutionPolicy Bypass -File scripts/check-dir-permissions.ps1 -Path "C:\Windows\system32\config\systemprofile\AppData\Local\rustdesk"
```

### 2. 功能测试
1. 以管理员身份启动服务
2. 远程连接到该主机
3. 检查日志确认使用了 ProgramData 路径
4. 验证 cm 子进程成功启动
5. 验证连接不会自动断开

### 3. 日志确认
查找日志中的关键信息：
```
[CM] Copied executable to user-accessible location: C:\ProgramData\RustDesk\...
[CM] Using executable: C:\ProgramData\RustDesk\1.4.3-jlc18\rustdesk.exe
[CM] CM subprocess started successfully (as root)
```

## 附加优化

### 1. 版本管理

添加自动清理旧版本：
```rust
fn cleanup_old_versions(base_dir: &Path) -> ResultType<()> {
    let current_version = crate::VERSION;

    for entry in std::fs::read_dir(base_dir)? {
        let entry = entry?;
        let path = entry.path();

        if path.is_dir() {
            if let Some(dir_name) = path.file_name() {
                let dir_name = dir_name.to_string_lossy();
                // 如果是版本目录但不是当前版本，删除
                if dir_name != current_version &&
                   dir_name.contains('.') {  // 版本号格式
                    log::info!("[CM] Removing old version: {:?}", path);
                    std::fs::remove_dir_all(&path).ok();
                }
            }
        }
    }
    Ok(())
}
```

### 2. 错误处理

增强错误处理和日志：
```rust
let exe_path = match get_user_accessible_exe() {
    Ok(path) => {
        log::info!("[CM] Using user-accessible exe: {}", path);
        path
    }
    Err(e) => {
        log::error!("[CM] Failed to get user-accessible exe: {:?}", e);
        log::error!("[CM] Falling back to current exe, may have permission issues");
        std::env::current_exe()?.to_string_lossy().to_string()
    }
};
```

## 总结

**问题**：cm子进程使用 systemprofile 目录的可执行文件，登录用户无权限访问

**解决方案**：将可执行文件复制到 `C:\ProgramData\RustDesk\<version>\` 目录

**优势**：
- 所有用户可访问
- 不修改系统权限
- 符合安全最佳实践
- 支持多用户场景

**工作量**：
- 新增1个辅助函数 (~50行)
- 修改cm启动逻辑 (~20行)
- 添加平台函数导出 (~5行)
- 总计约75行代码
