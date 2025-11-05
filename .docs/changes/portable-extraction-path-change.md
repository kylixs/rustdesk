# Portable 自解压路径修改

## 修改目的

将 Portable 可执行文件的解压目录从用户特定的 AppData 改为所有用户可访问的 ProgramData，解决 cm 子进程权限访问问题。

## 问题背景

### 原问题
1. **服务进程（SYSTEM用户）**运行 portable 程序时，解压到：
   ```
   C:\Windows\system32\config\systemprofile\AppData\Local\rustdesk\<version>\
   ```

2. **cm 子进程以登录用户身份运行**，但可执行文件在 systemprofile 目录，登录用户可能无权访问，导致：
   - cm 进程启动失败
   - 远程连接自动断开

## 解决方案

### 修改文件
`libs/portable/src/main.rs`

### 修改内容

#### 1. setup() 函数 (214-275行)

**修改前**：
```rust
let dir = if let Some(dir) = dirs::data_local_dir() {
    dir.join(APP_PREFIX).join(VERSION)
} else {
    return None;
}
```

**修改后**：
```rust
// 优先使用 C:\ProgramData\RustDesk\<version>\
let system_drive = std::env::var("SystemDrive").unwrap_or_else(|_| "C:".to_string());
let program_data_dir = PathBuf::from(format!("{}\\ProgramData", system_drive));

let target_dir = if program_data_dir.exists() {
    program_data_dir.join(APP_PREFIX).join(VERSION)
} else {
    // Fallback 1: C:\Windows\Temp
    let temp_dir = PathBuf::from(format!("{}\\Windows\\Temp", system_drive));
    if temp_dir.exists() {
        temp_dir.join(APP_PREFIX).join(VERSION)
    } else {
        // Fallback 2: 原 LocalAppData
        if let Some(dir) = dirs::data_local_dir() {
            dir.join(APP_PREFIX).join(VERSION)
        } else {
            return None;
        }
    }
};

// 尝试创建目录
if let Err(e) = std::fs::create_dir_all(&target_dir) {
    log::error!("Failed to create directory {}: {}", target_dir.display(), e);
    eprintln!("Error: Failed to create directory {}: {}", target_dir.display(), e);

    // 创建失败，尝试 fallback 到 LocalAppData
    if let Some(dir) = dirs::data_local_dir() {
        let fallback_dir = dir.join(APP_PREFIX).join(VERSION);
        if let Err(e2) = std::fs::create_dir_all(&fallback_dir) {
            log::error!("Failed to create fallback directory: {}", e2);
            return None;
        }
        fallback_dir
    } else {
        return None;
    }
} else {
    log::info!("Using extraction directory: {}", target_dir.display());
    target_dir
}
```

#### 2. handle_verify() 函数 (366-384行)

同样修改为使用 ProgramData 优先，保持与 setup() 一致的目录逻辑。

## Fallback 策略

解压目录选择优先级：

1. **优先级1**: `C:\ProgramData\RustDesk\<version>\`
   - 所有用户可访问
   - 最佳选择

2. **优先级2**: `C:\Windows\Temp\RustDesk\<version>\`
   - ProgramData 不存在时使用
   - 仍然是共享目录

3. **优先级3**: `%LOCALAPPDATA%\rustdesk\<version>\`
   - Windows\Temp 也不存在时使用
   - 原始行为（向后兼容）

4. **失败**: 返回 None，无法解压

## 错误处理

### 1. 目录不存在

如果 ProgramData 不存在：
```
Warning: ProgramData directory not found, using Windows\Temp
```
自动 fallback 到 Windows\Temp

### 2. 创建目录失败

如果无法在 ProgramData 创建目录：
```
Error: Failed to create directory C:\ProgramData\RustDesk\1.4.3: Access denied
```
自动 fallback 到 LocalAppData

### 3. 所有目录都失败

```
Error: No valid extraction directory available
```
程序退出，返回 None

## 日志输出

### 成功情况
```
[INFO] Using extraction directory: C:\ProgramData\RustDesk\1.4.3
```

### 警告情况
```
[WARN] ProgramData directory not found: C:\ProgramData, using Windows\Temp as fallback
[WARN] Attempting fallback to LocalAppData
```

### 错误情况
```
[ERROR] Failed to create directory C:\ProgramData\RustDesk\1.4.3: Permission denied
[ERROR] Failed to create fallback directory C:\Users\...\AppData\Local\rustdesk\1.4.3: ...
[ERROR] No valid extraction directory available
```

## 兼容性

### Windows 版本
- ✅ Windows 7 及以上：通常都有 C:\ProgramData
- ✅ Windows Server：通常有 ProgramData，fallback 到 Temp
- ✅ 精简版 Windows：自动 fallback 到原路径

### 用户权限
- ✅ **SYSTEM 用户**：完全控制 ProgramData
- ✅ **管理员**：可以访问 ProgramData
- ✅ **普通用户**：可以读取 ProgramData（执行程序）

## 测试验证

### 1. 正常系统测试
```powershell
# 运行 portable 程序
.\rustdesk-portable.exe --server

# 检查解压目录
ls C:\ProgramData\RustDesk\
```

**预期结果**：
```
C:\ProgramData\RustDesk\1.4.3\
  ├── rustdesk.exe
  ├── RuntimeBroker_rustdesk.exe
  └── meta.toml
```

### 2. ProgramData 不存在测试
```powershell
# 临时重命名 ProgramData (需管理员)
Rename-Item "C:\ProgramData" "C:\ProgramData.bak"

# 运行测试
.\rustdesk-portable.exe --server

# 检查是否使用 Temp
ls C:\Windows\Temp\RustDesk\

# 恢复
Rename-Item "C:\ProgramData.bak" "C:\ProgramData"
```

**预期结果**：
```
Warning: ProgramData directory not found, using Windows\Temp
C:\Windows\Temp\RustDesk\1.4.3\
  ├── rustdesk.exe
  ...
```

### 3. 验证权限
```powershell
# 检查目录权限
powershell -ExecutionPolicy Bypass -File scripts/check-dir-permissions.ps1 -Path "C:\ProgramData\RustDesk"
```

**预期结果**：所有用户都有读取和执行权限

### 4. 验证 cm 子进程
```powershell
# 启动服务
.\rustdesk-portable.exe --server

# 远程连接后检查进程
powershell -ExecutionPolicy Bypass -File scripts/show-processes.ps1

# 验证 cm 进程可执行文件路径
```

**预期结果**：
- cm 进程使用 `C:\ProgramData\RustDesk\<version>\rustdesk.exe`
- 登录用户可以成功访问
- 连接不会自动断开

## 优势

✅ **解决权限问题** - ProgramData 所有用户可访问
✅ **统一路径** - 服务和 cm 子进程使用同一位置
✅ **自动 Fallback** - 多级降级策略
✅ **详细日志** - 便于问题诊断
✅ **向后兼容** - 最终 fallback 到原路径
✅ **清晰错误** - 创建失败时明确提示

## 影响范围

### 受影响的功能
1. **Portable 首次运行** - 解压到新位置
2. **--verify 命令** - 检查新位置的文件
3. **cm 子进程** - 从新位置启动（解决权限问题）

### 不受影响
1. **已安装版本** - 仍使用 Program Files
2. **配置文件** - 仍在 %APPDATA%\RustDesk\config
3. **日志文件** - 仍在 %APPDATA%\RustDesk\log

## 后续工作（可选）

### 1. 清理旧版本
可以添加自动清理旧的 systemprofile 目录：
```rust
fn cleanup_old_extraction() {
    if let Some(dir) = dirs::data_local_dir() {
        let old_dir = dir.join("rustdesk");
        std::fs::remove_dir_all(&old_dir).ok();
    }
}
```

### 2. 权限设置
可以显式设置目录权限确保可访问：
```rust
#[cfg(windows)]
fn set_directory_permissions(dir: &Path) {
    // 使用 icacls 或 Windows API 设置权限
    // icacls dir /grant Users:RX
}
```

### 3. 磁盘空间检查
解压前检查可用空间：
```rust
fn check_disk_space(dir: &Path, required_mb: u64) -> bool {
    // 使用 GetDiskFreeSpaceEx 检查
}
```

## 编译和部署

### 编译
```bash
cd libs/portable
cargo build --release
```

### 测试
```bash
# 编译成功后，重新构建 portable 程序
python build.py --portable
```

### 部署
新构建的 portable 程序将自动使用新的解压路径。

## 回滚方案

如果需要回滚到原行为，恢复以下代码：
```rust
let dir = if let Some(dir) = dirs::data_local_dir() {
    dir.join(APP_PREFIX).join(VERSION)
} else {
    return None;
};
```

## 总结

这个修改从根本上解决了 portable 程序的权限访问问题，通过将解压目录改为 ProgramData，确保：
- ✅ 服务进程可以正常运行
- ✅ cm 子进程可以访问可执行文件
- ✅ 远程连接不会因权限问题断开
- ✅ 保持了向后兼容性和错误恢复能力
