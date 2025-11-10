# 构建时间戳版本号功能

## 概述

将构建时间戳自动添加到 Windows PE 文件的版本信息中，方便追踪和识别不同构建。该功能涵盖三种可执行文件：
1. Flutter GUI 可执行文件 (`rustdesk.exe`)
2. Portable 打包器可执行文件 (`rustdesk-portable-packer.exe`)
3. Portable 便携版可执行文件 (`rustdesk-<version>-x86_64.exe`)

## 版本号格式

```
<base_version>+<timestamp>
```

示例：
- 基础版本: `1.4.3-jlc18`
- 时间戳: `20251106-0913` (2025年11月6日 09:13)
- 完整版本: `1.4.3-jlc18+20251106-0913`

## 时间戳格式

- `YYYYMMDD-HHMM`
- 示例: `20251106-0913` 表示 2025年11月6日 09:13
- 使用构建机器的本地时间

## 实现方式

### 1. Flutter 可执行文件 (rustdesk.exe)

#### 主项目 build.rs

**文件**: `build.rs`

**关键修改**:
- 将条件编译从 `#[cfg(all(windows, feature = "inline"))]` 改为 `#[cfg(all(windows, any(feature = "inline", feature = "flutter")))]`
- 使用 `.set("ProductVersion", &full_version)` 而非 `.set_version_info()`

```rust
#[cfg(all(windows, any(feature = "inline", feature = "flutter")))]
fn build_manifest() {
    use std::io::Write;
    if std::env::var("PROFILE").unwrap() == "release" {
        // Read version from Cargo.toml
        let cargo_toml = std::fs::read_to_string("Cargo.toml").unwrap();
        let mut version = String::new();
        for line in cargo_toml.lines() {
            let ab: Vec<&str> = line.split('=').map(|x| x.trim()).collect();
            if ab.len() == 2 && ab[0] == "version" {
                version = ab[1].trim_matches('"').to_string();
                break;
            }
        }

        // Generate build timestamp
        let build_timestamp = chrono::Local::now().format("%Y%m%d-%H%M").to_string();
        let full_version = format!("{}+{}", version, build_timestamp);

        println!("cargo:warning=Building with version: {}", full_version);

        let mut res = winres::WindowsResource::new();
        res.set_icon("res/icon.ico")
            .set_language(winapi::um::winnt::MAKELANGID(
                winapi::um::winnt::LANG_ENGLISH,
                winapi::um::winnt::SUBLANG_ENGLISH_US,
            ))
            .set_manifest_file("res/manifest.xml")
            .set("ProductVersion", &full_version);

        match res.compile() {
            Err(e) => {
                write!(std::io::stderr(), "{}", e).unwrap();
                std::process::exit(1);
            }
            Ok(_) => {}
        }
    }
}
```

#### Flutter pubspec.yaml 动态修改

**文件**: `build.py`

**实现函数**: `update_flutter_version_with_timestamp()` 和 `restore_flutter_version()`

在 Flutter 构建前动态修改 `flutter/pubspec.yaml` 的版本号，添加时间戳，构建完成后恢复原始版本。

```python
def update_flutter_version_with_timestamp():
    """
    Update flutter/pubspec.yaml version with build timestamp.
    Backup original file and restore it after build.
    Returns: (backup_path, original_version, new_version, timestamp)
    """
    pubspec_path = "flutter/pubspec.yaml"
    backup_path = "flutter/pubspec.yaml.backup"

    # Backup original pubspec.yaml
    shutil.copy2(pubspec_path, backup_path)

    # Read current version
    with open(pubspec_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Find version line and add timestamp
    lines = content.split('\n')
    original_version = None
    timestamp_value = None
    new_lines = []

    for line in lines:
        if line.startswith('version:'):
            parts = line.split(':')
            if len(parts) >= 2:
                version_part = parts[1].strip()
                base_version = version_part.split('+')[0]
                original_version = version_part

                # Generate timestamp: YYYYMMDD-HHMM
                timestamp = datetime.now().strftime('%Y%m%d-%H%M')
                timestamp_value = timestamp

                # Create new version with timestamp
                new_version = f"{base_version}+{timestamp}"
                new_lines.append(f"version: {new_version}")
                print(f"Flutter version updated: {original_version} -> {new_version}")
                print(f"Build timestamp: {timestamp}")
            else:
                new_lines.append(line)
        else:
            new_lines.append(line)

    # Write updated content
    with open(pubspec_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(new_lines))

    return (backup_path, original_version, new_version, timestamp_value)

def restore_flutter_version(backup_path):
    """Restore original pubspec.yaml from backup"""
    pubspec_path = "flutter/pubspec.yaml"
    if os.path.exists(backup_path):
        shutil.copy2(backup_path, pubspec_path)
        os.remove(backup_path)
        print(f"Flutter version restored from backup")
```

### 2. Portable 打包器 (rustdesk-portable-packer.exe)

#### Portable build.rs

**文件**: `libs/portable/build.rs`

**关键特性**:
- 从临时文件 `target/build_timestamp.txt` 读取时间戳（由 build.py 写入）
- 如果文件不存在则生成新时间戳
- 确保与 Flutter exe 使用相同的时间戳

```rust
fn main() {
    #[cfg(windows)]
    {
        use std::io::Write;

        // Read version from workspace Cargo.toml
        let cargo_toml = std::fs::read_to_string("../../Cargo.toml").unwrap();
        let mut version = String::new();
        for line in cargo_toml.lines() {
            let ab: Vec<&str> = line.split('=').map(|x| x.trim()).collect();
            if ab.len() == 2 && ab[0] == "version" {
                version = ab[1].trim_matches('"').to_string();
                break;
            }
        }

        // Get build timestamp from temporary file (set by build.py) or generate new one
        // This ensures portable packer uses the same timestamp as the Flutter exe it packages
        let build_timestamp = std::fs::read_to_string("../../target/build_timestamp.txt")
            .ok()
            .and_then(|s| {
                let trimmed = s.trim();
                if trimmed.is_empty() {
                    None
                } else {
                    Some(trimmed.to_string())
                }
            })
            .unwrap_or_else(|| chrono::Local::now().format("%Y%m%d-%H%M").to_string());

        // Create full version with build timestamp: 1.4.3-jlc18+20251104-1945
        let full_version = format!("{}+{}", version, build_timestamp);

        println!("cargo:warning=Portable packer version: {}", full_version);

        let mut res = winres::WindowsResource::new();
        res.set_icon("../../res/icon.ico")
            .set_language(winapi::um::winnt::MAKELANGID(
                winapi::um::winnt::LANG_ENGLISH,
                winapi::um::winnt::SUBLANG_ENGLISH_US,
            ))
            .set_manifest_file("../../res/manifest.xml")
            .set("ProductVersion", &full_version);

        match res.compile() {
            Err(e) => {
                write!(std::io::stderr(), "{}", e).unwrap();
                std::process::exit(1);
            }
            Ok(_) => {}
        }
    }
}
```

**依赖**: `libs/portable/Cargo.toml`
```toml
[target.'cfg(target_os="windows")'.build-dependencies]
winres = "0.1"
winapi = { version = "0.3", features = [ "winnt", "pdh", "synchapi" ] }
chrono = "0.4"
```

### 3. 时间戳同步机制

为确保 Flutter exe 和 Portable packer 使用相同的时间戳，采用**临时文件传递**机制：

#### build.py 实现

在 `build_flutter_windows()` 函数中：

```python
def build_flutter_windows(version, features, skip_portable_pack):
    # ... cargo build for main library ...

    # Update Flutter version with timestamp before building
    backup_path, orig_ver, new_ver, build_timestamp = update_flutter_version_with_timestamp()

    try:
        os.chdir('flutter')
        system2('flutter build windows --release')
        os.chdir('..')
    finally:
        # Restore original version after build
        restore_flutter_version(backup_path)

    # ... copy files ...

    if skip_portable_pack:
        return

    # Write timestamp to temporary file for portable packer to use the same timestamp
    if build_timestamp:
        timestamp_file = 'target/build_timestamp.txt'
        os.makedirs('target', exist_ok=True)
        with open(timestamp_file, 'w') as f:
            f.write(build_timestamp)
        print(f"Wrote build timestamp {build_timestamp} to {timestamp_file} for portable packer")

    # ... build portable packer ...
    os.chdir('libs/portable')
    system2('pip3 install -r requirements.txt')
    system2(f'python3 ./generate.py -f ../../{flutter_build_dir_2} -o . -e ../../{flutter_build_dir_2}/rustdesk.exe')
    # ...
```

**流程**:
1. `build.py` 生成时间戳 (YYYYMMDD-HHMM)
2. 写入 Flutter `pubspec.yaml`
3. 构建 Flutter exe（包含此时间戳）
4. 恢复 `pubspec.yaml`
5. 将时间戳写入 `target/build_timestamp.txt`
6. 构建 portable packer（从文件读取相同时间戳）
7. Portable packer 打包 Flutter exe（两者时间戳一致）

## 查看方式

### 方法1: Windows 文件属性
1. 右键可执行文件 → 属性
2. 切换到"详细信息"标签页
3. 查看"产品版本"字段

### 方法2: PowerShell 单个文件
```powershell
$v = [System.Diagnostics.FileVersionInfo]::GetVersionInfo("rustdesk.exe")
Write-Host "Product Version: $($v.ProductVersion)"
```

输出示例：
```
Product Version: 1.4.3-jlc18+20251106-0913
```

### 方法3: 使用 show-processes.ps1 查看运行中进程
```powershell
.\scripts\show-processes.ps1 rustdesk -l
```

输出示例：
```
=== Process Information for: rustdesk ===

Found 2 process(es) matching 'rustdesk'

=== Flat List View ===

PID: 12345 | Name: rustdesk | User: NT AUTHORITY\SYSTEM | Session: 0
  Version: 1.4.3-jlc18+20251106-0913
  Path: C:\Program Files\RustDesk\rustdesk.exe
  Args: --service
  Parent PID: 1

PID: 23456 | Name: rustdesk | User: DESKTOP\User | Session: 1
  Version: 1.4.3-jlc18+20251106-0913
  Path: C:\Program Files\RustDesk\rustdesk.exe
  Parent PID: 4567
  TCP Ports:
    - 0.0.0.0:21118 (LISTEN)
```

**注意**: `show-processes.ps1` 已更新为优先显示 ProductVersion（包含时间戳）而非 FileVersion。

相关代码 (`scripts/show-processes.ps1:103-124`):
```powershell
function Get-ProcessVersion {
    param(
        [string]$ExecutablePath
    )

    if (-not $ExecutablePath -or -not (Test-Path $ExecutablePath)) {
        return $null
    }

    try {
        $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($ExecutablePath)
        # Prefer ProductVersion as it contains build timestamp
        if ($versionInfo.ProductVersion) {
            return $versionInfo.ProductVersion
        } elseif ($versionInfo.FileVersion) {
            return $versionInfo.FileVersion
        }
    } catch {
        # Silently ignore errors
    }

    return $null
}
```

### 方法4: 验证检查脚本

#### 检查 Flutter exe 版本
```powershell
.\check-flutter-version.ps1
```

#### 检查 Portable exe 版本
```powershell
.\check-portable-version.ps1
```

### 方法5: 从版本号中提取时间戳
```powershell
$file = Get-Item ./rustdesk.exe
$versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($file.FullName)
$productVersion = $versionInfo.ProductVersion

# 提取构建时间
if ($productVersion -match '\+(\d{8})-(\d{4})$') {
    $buildDate = $matches[1]  # 20251106
    $buildTime = $matches[2]  # 0913

    # 格式化输出
    $year = $buildDate.Substring(0, 4)
    $month = $buildDate.Substring(4, 2)
    $day = $buildDate.Substring(6, 2)
    $hour = $buildTime.Substring(0, 2)
    $minute = $buildTime.Substring(2, 2)

    Write-Host "Built on: $year-$month-$day at $hour:$minute"
}
```

输出：
```
Built on: 2025-11-06 at 09:13
```

## 优点

1. **易于追踪**: 一眼就能看出文件是什么时候构建的
2. **不侵入代码**: 只修改 PE 文件的版本资源，不影响代码逻辑
3. **自动化**: 每次构建自动生成，无需手动维护
4. **兼容性**: 不影响现有版本号比较逻辑
5. **可解析**: 时间戳格式固定，方便脚本解析
6. **一致性**: Flutter exe 和 Portable exe 使用相同的时间戳

## 使用场景

### 场景1: 快速识别版本
在诊断脚本中可以快速识别运行的是哪个构建：

```powershell
$exe = "C:\Program Files\RustDesk\RustDesk.exe"
$v = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
Write-Host "Running version: $($v.ProductVersion)"
```

输出：
```
Running version: 1.4.3-jlc18+20251106-0913
```

### 场景2: 验证 Portable 与 Flutter exe 版本一致性
```powershell
$flutterExe = ".\rustdesk\rustdesk.exe"
$portableExe = ".\SignOutput\rustdesk-1.4.3-jlc18-x86_64.exe"

$flutterVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($flutterExe).ProductVersion
$portableVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($portableExe).ProductVersion

Write-Host "Flutter exe version:  $flutterVersion"
Write-Host "Portable exe version: $portableVersion"

if ($flutterVersion -eq $portableVersion) {
    Write-Host "✓ Versions match!" -ForegroundColor Green
} else {
    Write-Host "✗ Version mismatch!" -ForegroundColor Red
}
```

### 场景3: 比较版本新旧
```powershell
# 从版本号中提取时间戳并比较
function Get-BuildTimestamp($version) {
    if ($version -match '\+(\d{8})-(\d{4})$') {
        return "${matches[1]}${matches[2]}"  # 202511060913
    }
    return "000000000000"
}

$version1 = "1.4.3-jlc18+20251106-0800"
$version2 = "1.4.3-jlc18+20251106-0913"

$ts1 = Get-BuildTimestamp $version1
$ts2 = Get-BuildTimestamp $version2

if ($ts2 -gt $ts1) {
    Write-Host "Version 2 is newer (built at 09:13 vs 08:00)"
}
```

### 场景4: 自动化测试
在自动化测试中验证是否使用了最新构建：

```powershell
$installedExe = "C:\Program Files\RustDesk\RustDesk.exe"
$latestBuild = ".\SignOutput\rustdesk-1.4.3-jlc18-x86_64.exe"

$installedVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($installedExe).ProductVersion
$latestVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($latestBuild).ProductVersion

if ($installedVersion -ne $latestVersion) {
    Write-Host "WARNING: Installed version ($installedVersion) differs from latest build ($latestVersion)"
    exit 1
}

Write-Host "✓ Using latest build: $installedVersion" -ForegroundColor Green
```

## 技术细节

### Windows PE 版本资源

- **ProductVersion**: 产品版本，可以是任意字符串格式，用于显示给用户
- **FileVersion**: 文件版本，通常是数字格式 (major.minor.patch.build)

本实现使用 **ProductVersion** 字段来存储带时间戳的完整版本号，因为它支持任意字符串格式。

### winres API

使用 `winres` crate 的 0.1 版本：
- `.set("ProductVersion", &full_version)` - 设置产品版本字符串
- ~~`.set_version_info(winres::VersionInfo::PRODUCTVERSION, &full_version)`~~ - 旧API，不兼容字符串参数

### 条件编译

主项目 `build.rs`:
```rust
#[cfg(all(windows, any(feature = "inline", feature = "flutter")))]
```

- `windows`: 仅 Windows 平台
- `any(feature = "inline", feature = "flutter")`: inline 或 flutter 特性
- 仅 `release` profile

Portable `build.rs`:
```rust
#[cfg(windows)]
```

- 仅 Windows 平台
- 所有 profile（但通常只构建 release）

### 文件结构

```
rustdesk/
├── build.rs                           # 主项目构建脚本
├── Cargo.toml                         # 版本定义: version = "1.4.3-jlc18"
├── build.py                           # Python 构建脚本
├── target/
│   └── build_timestamp.txt            # 临时时间戳文件 (build.py 写入)
├── flutter/
│   ├── pubspec.yaml                   # Flutter 版本定义
│   └── pubspec.yaml.backup            # 临时备份（构建后删除）
├── libs/
│   └── portable/
│       ├── build.rs                   # Portable 构建脚本 (读取 build_timestamp.txt)
│       └── Cargo.toml                 # 添加 chrono 依赖
└── scripts/
    ├── show-processes.ps1             # 进程信息查看脚本 (显示 ProductVersion)
    ├── check-flutter-version.ps1      # Flutter exe 版本检查
    └── check-portable-version.ps1     # Portable exe 版本检查
```

## 注意事项

1. **平台限制**: 只影响 Windows 平台
2. **构建模式**: 主项目只在 Release 构建时添加时间戳
3. **时区**: 时间戳使用构建机器的本地时间，注意时区差异
4. **语义化版本**: 时间戳在 `+` 后面，符合 [Semantic Versioning 2.0.0](https://semver.org/) 构建元数据格式
5. **临时文件**: `target/build_timestamp.txt` 是临时文件，每次构建时覆盖
6. **备份文件**: `flutter/pubspec.yaml.backup` 在构建完成后自动删除
7. **时间戳一致性**: Flutter exe 和 Portable exe 应该有相同的时间戳（通过文件传递机制保证）

## 验证清单

构建完成后，应验证以下内容：

- [ ] Flutter exe 包含时间戳版本号
- [ ] Portable packer exe 包含时间戳版本号
- [ ] Portable 便携版 exe 包含时间戳版本号
- [ ] Flutter exe 和 Portable exe 的时间戳相同
- [ ] `show-processes.ps1` 正确显示带时间戳的版本
- [ ] `flutter/pubspec.yaml` 已恢复到原始版本（无时间戳）
- [ ] `flutter/pubspec.yaml.backup` 已被删除

验证命令：
```powershell
# 检查 Flutter exe
[System.Diagnostics.FileVersionInfo]::GetVersionInfo(".\rustdesk\rustdesk.exe").ProductVersion

# 检查 Portable packer
[System.Diagnostics.FileVersionInfo]::GetVersionInfo(".\target\release\rustdesk-portable-packer.exe").ProductVersion

# 检查 Portable 便携版
[System.Diagnostics.FileVersionInfo]::GetVersionInfo(".\SignOutput\rustdesk-*-x86_64.exe").ProductVersion

# 检查 pubspec.yaml 已恢复
Get-Content flutter\pubspec.yaml | Select-String "version:"

# 检查备份文件已删除
Test-Path flutter\pubspec.yaml.backup  # 应返回 False
```

## 相关文档

- [语义化版本 2.0.0](https://semver.org/lang/zh-CN/)
- [winres crate 文档](https://docs.rs/winres/)
- [PE 文件版本资源](https://learn.microsoft.com/en-us/windows/win32/menurc/versioninfo-resource)
- [chrono crate 文档](https://docs.rs/chrono/)
- [FileVersionInfo Class (C#)](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.fileversioninfo)
