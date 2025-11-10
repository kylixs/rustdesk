# Windows Portable 版本验证功能设计方案

**文档版本**: 1.0
**创建日期**: 2025-01-21
**最后更新**: 2025-01-21
**状态**: 设计阶段

## 目录

- [一、需求分析](#一需求分析)
- [二、设计方案](#二设计方案)
- [三、技术实现要点](#三技术实现要点)
- [四、性能指标](#四性能指标)
- [五、实现步骤](#五实现步骤)
- [六、CLI 使用示例](#六-cli-使用示例)

---

## 一、需求分析

### 1.1 核心需求

1. **CLI 命令**：添加一个命令行工具，用于验证 portable 解压目录下文件的版本和文件完整性（SHA256/MD5）
2. **增强日志**：portable 启动解压时输出详细的日志信息
3. **快速检查**：portable 启动时使用轻量级验证，确保性能不受影响
4. **完整检查**：CLI 命令提供完整的哈希验证，用于诊断和调试

### 1.2 使用场景

- **CLI 完整验证**：开发/调试时验证 portable 包的完整性和正确性
- **启动快速检查**：运行时快速验证关键文件，确保启动性能
- **问题诊断**：用户报告问题时，通过 CLI 命令获取详细诊断信息

### 1.3 设计目标

| 模式 | 验证内容 | 性能目标 | 使用场景 |
|------|----------|----------|----------|
| **快速检查** | 存在性 + 版本 + 大小 | < 50ms | Portable 启动时 |
| **完整验证** | 存在性 + 版本 + 哈希 | < 2s | CLI 诊断工具 |

---

## 二、设计方案

### 2.1 CLI 命令设计（完整验证模式）

#### 命令名称

```bash
rustdesk --verify-portable [OPTIONS]
```

#### 参数说明

```
--verify-portable [PATH]     验证 portable 解压目录
  [PATH]                     portable 目录路径（默认：当前目录）
  --json                     以 JSON 格式输出结果
  --hash-algorithm <ALGO>    指定哈希算法：sha256（默认）、sha1、md5
  --skip-hash                跳过哈希验证，仅检查版本
```

#### 输出内容示例

```
RustDesk Portable Verification Report
========================================
Portable Directory: C:\path\to\portable
Expected Version: 1.4.3-jc12
Hash Algorithm: SHA256

Verifying files...
  ✓ rustdesk.exe
    Version: 1.4.3-jc12 (OK)
    SHA256:  a1b2c3d4... (OK)
    Size:    15.2 MB

  ✓ libsciter.dll
    Version: 4.4.8.30 (OK)
    SHA256:  e5f6g7h8... (OK)
    Size:    8.5 MB

  ✗ WindowInjection.dll
    Version: 1.0.0.0 (expected: 1.0.1.0) [WARNING]
    SHA256:  i9j0k1l2... (MISMATCH) [ERROR]
    Expected: m3n4o5p6...
    Size:    156 KB

  ✗ printer_driver_adapter.dll
    Status: MISSING [ERROR]

  ✓ data/flutter_assets/
    Files: 1,234 checked, all OK

Summary:
========================================
  Total files: 45
  Passed: 42
  Warnings: 1 (version mismatch)
  Errors: 2 (hash mismatch + missing file)
  Total size: 58.3 MB
  Verification time: 2.34s

Status: FAILED ✗
```

### 2.2 Portable 启动快速检查（性能优先模式）

#### 2.2.1 检查策略

**快速检查原则**：
- ✅ 仅检查关键文件存在性
- ✅ 验证主程序版本号
- ✅ 检查文件大小（快速，开销低）
- ❌ 不计算哈希值（性能开销大）
- ✅ 总耗时目标：< 50ms

#### 2.2.2 检查项目

```rust
// 启动时的快速检查
pub struct QuickVerification {
    // 1. 关键文件存在性检查（仅检查是否存在）
    critical_files: Vec<&'static str>,

    // 2. 主程序版本检查（读取 PE 文件版本信息，~5ms）
    main_exe_version: bool,

    // 3. 文件大小合理性检查（对比预期大小范围，~1ms）
    file_size_check: bool,
}

const CRITICAL_FILES: &[&str] = &[
    "rustdesk.exe",
    "libsciter.dll",
];

const OPTIONAL_FILES: &[&str] = &[
    "WindowInjection.dll",
    "printer_driver_adapter.dll",
];
```

#### 2.2.3 快速检查日志输出

```
[INFO] RustDesk Portable starting...
[INFO] Package version: 1.4.3-jc12
[INFO] Quick verification: checking 2 critical files...
[INFO] ✓ All critical files present
[INFO] ✓ Main executable version: 1.4.3-jc12
[WARN] Optional file missing: printer_driver_adapter.dll (printing may not work)
[INFO] Quick verification completed in 23ms
[INFO] Starting RustDesk...
```

### 2.3 哈希验证设计

#### 2.3.1 哈希清单文件

**位置**：打包时生成 `checksums.txt`，嵌入到 portable 包中

**格式**：
```
# RustDesk Portable Package Checksums
# Version: 1.4.3-jc12
# Algorithm: SHA256
# Generated: 2025-01-21 12:34:56

a1b2c3d4e5f6g7h8...  rustdesk.exe
e5f6g7h8i9j0k1l2...  libsciter.dll
i9j0k1l2m3n4o5p6...  WindowInjection.dll
m3n4o5p6q7r8s9t0...  printer_driver_adapter.dll
...
```

**嵌入方式**：
```rust
// 编译时嵌入（libs/portable/src/main.rs）
const CHECKSUMS: &str = include_str!("../checksums.txt");
```

#### 2.3.2 哈希算法选择

| 算法 | 性能 | 安全性 | 用途 |
|------|------|--------|------|
| **SHA256** | 中等 (50MB/s) | 高 | CLI 完整验证（默认） |
| **SHA1** | 快速 (100MB/s) | 中 | CLI 快速验证 |
| **MD5** | 最快 (150MB/s) | 低 | 兼容性验证 |
| **文件大小** | 极快 | 低 | 启动快速检查 |

**性能对比**（50MB 文件）：
- SHA256: ~1000ms
- SHA1: ~500ms
- MD5: ~330ms
- 文件大小: ~1ms ✅

#### 2.3.3 实现库选择

```toml
# Cargo.toml
[dependencies]
sha2 = "0.10"      # SHA256
sha1 = "0.10"      # SHA1
md-5 = "0.10"      # MD5
```

### 2.4 数据结构设计

#### 2.4.1 验证模式枚举

```rust
#[derive(Debug, Clone, Copy)]
pub enum VerificationMode {
    /// CLI 完整验证：版本 + 哈希 + 文件完整性
    Full {
        hash_algorithm: HashAlgorithm,
    },
    /// 启动快速检查：仅存在性 + 版本 + 大小
    Quick,
}

#[derive(Debug, Clone, Copy)]
pub enum HashAlgorithm {
    Sha256,
    Sha1,
    Md5,
    None,  // 跳过哈希验证
}
```

#### 2.4.2 文件验证信息

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileVerificationInfo {
    pub file_path: PathBuf,
    pub file_type: FileType,
    pub checks: VerificationChecks,
}

#[derive(Debug, Clone, Copy)]
pub enum FileType {
    Critical,   // 关键文件，缺失为 ERROR
    Optional,   // 可选文件，缺失为 WARNING
    Resource,   // 资源文件，仅统计
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerificationChecks {
    // 存在性检查
    pub exists: Option<CheckResult>,

    // 文件大小检查
    pub size: Option<SizeCheckResult>,

    // 版本检查（仅 EXE/DLL）
    pub version: Option<VersionCheckResult>,

    // 哈希检查（仅 Full 模式）
    pub hash: Option<HashCheckResult>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CheckResult {
    pub status: VerificationStatus,
    pub message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SizeCheckResult {
    pub actual_size: u64,
    pub expected_size: Option<u64>,
    pub status: VerificationStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HashCheckResult {
    pub algorithm: String,
    pub actual_hash: String,
    pub expected_hash: Option<String>,
    pub status: VerificationStatus,
    pub compute_time_ms: u64,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum VerificationStatus {
    Ok,
    Warning,
    Error,
    Skipped,
}
```

### 2.5 实现位置和架构

```
src/
├── portable_verify/
│   ├── mod.rs              # 模块入口
│   ├── verify.rs           # 验证主逻辑
│   ├── hash.rs             # 哈希计算
│   ├── version.rs          # 版本读取（Windows PE）
│   ├── checksums.rs        # 哈希清单解析
│   └── report.rs           # 结果输出（text/json）
├── cli_help.rs             # 添加帮助文档
└── core_main.rs            # CLI 命令处理

libs/portable/
├── src/
│   ├── main.rs             # 添加启动快速检查
│   └── quick_check.rs      # 快速检查逻辑
├── checksums.txt           # 哈希清单（构建时生成）
└── build.rs                # 构建脚本（生成 checksums.txt）
```

---

## 三、技术实现要点

### 3.1 哈希清单生成（构建时）

**在 `libs/portable/build.rs` 中实现**：

```rust
// libs/portable/build.rs
use sha2::{Sha256, Digest};
use std::fs::{self, File};
use std::io::Read;

fn main() {
    // 从环境变量获取源目录
    let source_dir = env::var("PORTABLE_SOURCE_DIR")
        .expect("PORTABLE_SOURCE_DIR not set");

    // 生成 checksums.txt
    generate_checksums(&source_dir, "checksums.txt").unwrap();
}

fn generate_checksums(source_dir: &str, output: &str) -> std::io::Result<()> {
    let mut checksums = String::new();
    checksums.push_str(&format!("# RustDesk Portable Package Checksums\n"));
    checksums.push_str(&format!("# Version: {}\n", env!("CARGO_PKG_VERSION")));
    checksums.push_str(&format!("# Algorithm: SHA256\n\n"));

    for entry in fs::read_dir(source_dir)? {
        let entry = entry?;
        let path = entry.path();

        if path.is_file() {
            let hash = compute_file_hash(&path)?;
            let filename = path.file_name().unwrap().to_string_lossy();
            checksums.push_str(&format!("{} {}\n", hash, filename));
        }
    }

    fs::write(output, checksums)?;
    Ok(())
}

fn compute_file_hash(path: &Path) -> std::io::Result<String> {
    let mut file = File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = [0; 8192];

    loop {
        let n = file.read(&mut buffer)?;
        if n == 0 { break; }
        hasher.update(&buffer[..n]);
    }

    Ok(format!("{:x}", hasher.finalize()))
}
```

**在 `build.ps1` 中调用**：

```powershell
# Task 19: 构建自解压可执行文件
if ($EnablePortable) {
    Write-Section "Task 19: 构建自解压可执行文件"

    # 生成哈希清单
    Write-Info "生成哈希清单..."
    $env:PORTABLE_SOURCE_DIR = ".\rustdesk\"

    Push-Location libs\portable
    cargo build --release
    Pop-Location

    # ... 后续步骤
}
```

### 3.2 快速检查实现（启动时）

```rust
// libs/portable/src/quick_check.rs

use std::time::Instant;
use std::path::{Path, PathBuf};
use std::ops::Range;

pub struct QuickChecker {
    extract_dir: PathBuf,
    expected_version: String,
}

impl QuickChecker {
    pub fn new(extract_dir: PathBuf, expected_version: String) -> Self {
        Self { extract_dir, expected_version }
    }

    pub fn verify(&self) -> QuickVerificationResult {
        let start = Instant::now();
        let mut result = QuickVerificationResult::default();

        // 1. 检查关键文件存在性（~5ms）
        for file in CRITICAL_FILES {
            let path = self.extract_dir.join(file);
            if !path.exists() {
                result.errors.push(format!("Critical file missing: {}", file));
                log::error!("Critical file missing: {}", file);
            } else {
                log::debug!("✓ Critical file found: {}", file);
            }
        }

        // 2. 检查可选文件（~5ms）
        for file in OPTIONAL_FILES {
            let path = self.extract_dir.join(file);
            if !path.exists() {
                result.warnings.push(format!("Optional file missing: {}", file));
                log::warn!("Optional file missing: {}", file);
            } else {
                log::debug!("✓ Optional file found: {}", file);
            }
        }

        // 3. 验证主程序版本（~10ms）
        let exe_path = self.extract_dir.join("rustdesk.exe");
        match get_file_version(&exe_path) {
            Ok(version) => {
                log::info!("Main executable version: {}", version);
                if version != self.expected_version {
                    let msg = format!(
                        "Version mismatch: expected {}, found {}",
                        self.expected_version, version
                    );
                    result.warnings.push(msg.clone());
                    log::warn!("{}", msg);
                }
            }
            Err(e) => {
                let msg = format!("Failed to read version: {}", e);
                result.errors.push(msg.clone());
                log::error!("{}", msg);
            }
        }

        // 4. 检查文件大小合理性（~5ms）
        for (file, expected_size_range) in EXPECTED_SIZES {
            let path = self.extract_dir.join(file);
            if let Ok(metadata) = std::fs::metadata(&path) {
                let size = metadata.len();
                if !expected_size_range.contains(&size) {
                    let msg = format!(
                        "Unexpected file size: {} ({} bytes, expected: {}-{})",
                        file, size, expected_size_range.start, expected_size_range.end
                    );
                    result.warnings.push(msg.clone());
                    log::warn!("{}", msg);
                }
            }
        }

        result.elapsed = start.elapsed();
        log::info!(
            "Quick verification completed in {}ms ({} errors, {} warnings)",
            result.elapsed.as_millis(),
            result.errors.len(),
            result.warnings.len()
        );

        result
    }
}

#[derive(Debug, Default)]
pub struct QuickVerificationResult {
    pub errors: Vec<String>,
    pub warnings: Vec<String>,
    pub elapsed: std::time::Duration,
}

impl QuickVerificationResult {
    pub fn is_ok(&self) -> bool {
        self.errors.is_empty()
    }
}

const CRITICAL_FILES: &[&str] = &[
    "rustdesk.exe",
    "libsciter.dll",
];

const OPTIONAL_FILES: &[&str] = &[
    "WindowInjection.dll",
    "printer_driver_adapter.dll",
];

const EXPECTED_SIZES: &[(&str, Range<u64>)] = &[
    ("rustdesk.exe", 10_000_000..20_000_000),      // 10-20 MB
    ("libsciter.dll", 5_000_000..15_000_000),      // 5-15 MB
    ("WindowInjection.dll", 100_000..500_000),     // 100-500 KB
];

// Windows 平台读取 PE 文件版本
#[cfg(target_os = "windows")]
fn get_file_version(path: &Path) -> Result<String, Box<dyn std::error::Error>> {
    use std::ffi::OsStr;
    use std::os::windows::ffi::OsStrExt;
    use winapi::um::winver::{GetFileVersionInfoSizeW, GetFileVersionInfoW, VerQueryValueW};
    use winapi::um::winnt::LPCWSTR;

    let path_wide: Vec<u16> = OsStr::new(path)
        .encode_wide()
        .chain(std::iter::once(0))
        .collect();

    unsafe {
        let size = GetFileVersionInfoSizeW(path_wide.as_ptr(), std::ptr::null_mut());
        if size == 0 {
            return Err("Failed to get version info size".into());
        }

        let mut buffer = vec![0u8; size as usize];
        if GetFileVersionInfoW(
            path_wide.as_ptr(),
            0,
            size,
            buffer.as_mut_ptr() as *mut _,
        ) == 0 {
            return Err("Failed to get version info".into());
        }

        let mut version_ptr: *mut u8 = std::ptr::null_mut();
        let mut version_len: u32 = 0;
        let sub_block: Vec<u16> = OsStr::new("\\")
            .encode_wide()
            .chain(std::iter::once(0))
            .collect();

        if VerQueryValueW(
            buffer.as_ptr() as *const _,
            sub_block.as_ptr(),
            &mut version_ptr as *mut _ as *mut _,
            &mut version_len,
        ) == 0 {
            return Err("Failed to query version value".into());
        }

        // 解析 VS_FIXEDFILEINFO 结构
        let file_info = version_ptr as *const winapi::um::verrsrc::VS_FIXEDFILEINFO;
        let major = ((*file_info).dwFileVersionMS >> 16) & 0xFFFF;
        let minor = (*file_info).dwFileVersionMS & 0xFFFF;
        let patch = ((*file_info).dwFileVersionLS >> 16) & 0xFFFF;
        let build = (*file_info).dwFileVersionLS & 0xFFFF;

        Ok(format!("{}.{}.{}.{}", major, minor, patch, build))
    }
}

#[cfg(not(target_os = "windows"))]
fn get_file_version(_path: &Path) -> Result<String, Box<dyn std::error::Error>> {
    Err("Version reading not supported on this platform".into())
}
```

**在 `libs/portable/src/main.rs` 中集成**：

```rust
mod quick_check;
use quick_check::QuickChecker;

fn main() {
    // ... 现有解压逻辑

    log::info!("Extraction completed, running quick verification...");

    let checker = QuickChecker::new(
        extract_dir.clone(),
        env!("CARGO_PKG_VERSION").to_string(),
    );

    let result = checker.verify();

    if !result.is_ok() {
        log::warn!("Quick verification found {} errors", result.errors.len());
        for error in &result.errors {
            log::error!("  - {}", error);
        }
    }

    if !result.warnings.is_empty() {
        log::warn!("Quick verification found {} warnings", result.warnings.len());
        for warning in &result.warnings {
            log::warn!("  - {}", warning);
        }
    }

    // ... 继续启动主程序
}
```

### 3.3 完整验证实现（CLI）

```rust
// src/portable_verify/verify.rs

use std::path::{Path, PathBuf};
use std::collections::HashMap;
use std::time::Instant;

pub struct FullVerifier {
    portable_dir: PathBuf,
    mode: VerificationMode,
    checksums: HashMap<String, String>,
}

impl FullVerifier {
    pub fn new(portable_dir: PathBuf, mode: VerificationMode) -> Result<Self> {
        let checksums = Self::load_checksums(&portable_dir)?;
        Ok(Self {
            portable_dir,
            mode,
            checksums,
        })
    }

    fn load_checksums(dir: &Path) -> Result<HashMap<String, String>> {
        let checksum_file = dir.join("checksums.txt");
        if !checksum_file.exists() {
            return Err(anyhow!("checksums.txt not found"));
        }

        let content = std::fs::read_to_string(checksum_file)?;
        let mut map = HashMap::new();

        for line in content.lines() {
            if line.starts_with('#') || line.trim().is_empty() {
                continue;
            }

            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 2 {
                map.insert(parts[1].to_string(), parts[0].to_string());
            }
        }

        Ok(map)
    }

    pub fn verify(&self) -> VerificationResult {
        let start = Instant::now();
        let mut result = VerificationResult::default();
        result.portable_dir = self.portable_dir.clone();
        result.expected_version = env!("CARGO_PKG_VERSION").to_string();

        log::info!("Starting full verification of {}", self.portable_dir.display());

        // 遍历所有文件
        for (filename, expected_hash) in &self.checksums {
            let file_path = self.portable_dir.join(filename);
            let mut file_info = FileVerificationInfo::new(file_path.clone());

            // 1. 存在性检查
            file_info.checks.exists = Some(self.check_exists(&file_path));

            if file_path.exists() {
                // 2. 文件大小检查
                file_info.checks.size = Some(self.check_size(&file_path));

                // 3. 版本检查（仅 PE 文件）
                if is_pe_file(&file_path) {
                    file_info.checks.version = Some(self.check_version(&file_path));
                }

                // 4. 哈希检查
                if let VerificationMode::Full { hash_algorithm } = self.mode {
                    if hash_algorithm != HashAlgorithm::None {
                        file_info.checks.hash = Some(
                            self.check_hash(&file_path, expected_hash, hash_algorithm)
                        );
                    }
                }
            }

            result.files.push(file_info);
        }

        result.elapsed = start.elapsed();
        result.compute_summary();

        log::info!(
            "Verification completed in {:.2}s: {} passed, {} warnings, {} errors",
            result.elapsed.as_secs_f64(),
            result.summary.passed,
            result.summary.warnings,
            result.summary.errors
        );

        result
    }

    fn check_exists(&self, path: &Path) -> CheckResult {
        let exists = path.exists();
        CheckResult {
            status: if exists {
                VerificationStatus::Ok
            } else {
                VerificationStatus::Error
            },
            message: if !exists {
                Some("File not found".to_string())
            } else {
                None
            },
        }
    }

    fn check_size(&self, path: &Path) -> SizeCheckResult {
        match std::fs::metadata(path) {
            Ok(metadata) => SizeCheckResult {
                actual_size: metadata.len(),
                expected_size: None,
                status: VerificationStatus::Ok,
            },
            Err(e) => SizeCheckResult {
                actual_size: 0,
                expected_size: None,
                status: VerificationStatus::Error,
            },
        }
    }

    fn check_version(&self, path: &Path) -> VersionCheckResult {
        // 使用 quick_check.rs 中的 get_file_version
        match crate::platform::get_file_version(path) {
            Ok(version) => VersionCheckResult {
                actual_version: Some(version.clone()),
                expected_version: Some(env!("CARGO_PKG_VERSION").to_string()),
                status: if version.starts_with(env!("CARGO_PKG_VERSION")) {
                    VerificationStatus::Ok
                } else {
                    VerificationStatus::Warning
                },
            },
            Err(e) => VersionCheckResult {
                actual_version: None,
                expected_version: Some(env!("CARGO_PKG_VERSION").to_string()),
                status: VerificationStatus::Error,
            },
        }
    }

    fn check_hash(&self, path: &Path, expected: &str, algo: HashAlgorithm)
        -> HashCheckResult
    {
        let start = Instant::now();

        match compute_file_hash(path, algo) {
            Ok(actual) => {
                let elapsed = start.elapsed().as_millis() as u64;
                HashCheckResult {
                    algorithm: format!("{:?}", algo),
                    actual_hash: actual.clone(),
                    expected_hash: Some(expected.to_string()),
                    status: if actual.to_lowercase() == expected.to_lowercase() {
                        VerificationStatus::Ok
                    } else {
                        VerificationStatus::Error
                    },
                    compute_time_ms: elapsed,
                }
            }
            Err(e) => {
                HashCheckResult {
                    algorithm: format!("{:?}", algo),
                    actual_hash: String::new(),
                    expected_hash: Some(expected.to_string()),
                    status: VerificationStatus::Error,
                    compute_time_ms: 0,
                }
            }
        }
    }
}

fn is_pe_file(path: &Path) -> bool {
    path.extension()
        .and_then(|s| s.to_str())
        .map(|s| s.eq_ignore_ascii_case("exe") || s.eq_ignore_ascii_case("dll"))
        .unwrap_or(false)
}
```

### 3.4 哈希计算优化

```rust
// src/portable_verify/hash.rs

use sha2::{Sha256, Digest as Sha2Digest};
use sha1::{Sha1, Digest as Sha1Digest};
use md5::{Md5, Digest as Md5Digest};
use std::fs::File;
use std::io::Read;
use std::path::Path;

pub fn compute_file_hash(path: &Path, algorithm: HashAlgorithm)
    -> Result<String, Box<dyn std::error::Error>>
{
    let mut file = File::open(path)?;
    let mut buffer = vec![0; 8192]; // 8KB buffer

    match algorithm {
        HashAlgorithm::Sha256 => {
            let mut hasher = Sha256::new();
            loop {
                let n = file.read(&mut buffer)?;
                if n == 0 { break; }
                hasher.update(&buffer[..n]);
            }
            Ok(format!("{:x}", hasher.finalize()))
        }
        HashAlgorithm::Sha1 => {
            let mut hasher = Sha1::new();
            loop {
                let n = file.read(&mut buffer)?;
                if n == 0 { break; }
                hasher.update(&buffer[..n]);
            }
            Ok(format!("{:x}", hasher.finalize()))
        }
        HashAlgorithm::Md5 => {
            let mut hasher = Md5::new();
            loop {
                let n = file.read(&mut buffer)?;
                if n == 0 { break; }
                hasher.update(&buffer[..n]);
            }
            Ok(format!("{:x}", hasher.finalize()))
        }
        HashAlgorithm::None => {
            Err("Hash algorithm not specified".into())
        }
    }
}
```

### 3.5 CLI 命令处理

```rust
// src/core_main.rs

} else if args[0] == "--verify-portable" {
    log::info!("Starting portable verification");

    let portable_dir = if args.len() > 1 {
        PathBuf::from(&args[1])
    } else {
        std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
    };

    let json_output = args.contains(&"--json".to_string());
    let skip_hash = args.contains(&"--skip-hash".to_string());

    let hash_algorithm = if skip_hash {
        HashAlgorithm::None
    } else if let Some(pos) = args.iter().position(|a| a == "--hash-algorithm") {
        if let Some(algo_str) = args.get(pos + 1) {
            match algo_str.to_lowercase().as_str() {
                "sha256" => HashAlgorithm::Sha256,
                "sha1" => HashAlgorithm::Sha1,
                "md5" => HashAlgorithm::Md5,
                _ => {
                    eprintln!("Unknown hash algorithm: {}", algo_str);
                    eprintln!("Supported: sha256, sha1, md5");
                    std::process::exit(1);
                }
            }
        } else {
            HashAlgorithm::Sha256
        }
    } else {
        HashAlgorithm::Sha256
    };

    let mode = VerificationMode::Full { hash_algorithm };

    match FullVerifier::new(portable_dir, mode) {
        Ok(verifier) => {
            let result = verifier.verify();

            if json_output {
                println!("{}", serde_json::to_string_pretty(&result).unwrap());
            } else {
                crate::portable_verify::report::print_text_report(&result);
            }

            std::process::exit(if result.summary.overall_status { 0 } else { 1 });
        }
        Err(e) => {
            eprintln!("Verification failed: {}", e);
            std::process::exit(1);
        }
    }

    return None;
}
```

---

## 四、性能指标

### 4.1 快速检查（启动时）

| 操作 | 文件数 | 预计耗时 |
|------|--------|----------|
| 文件存在性检查 | 5 个关键文件 | ~5ms |
| 版本读取 | 1 个 EXE | ~10ms |
| 文件大小检查 | 5 个文件 | ~5ms |
| 日志输出 | - | ~5ms |
| **总计** | - | **~25ms** ✅ |

### 4.2 完整验证（CLI）

| 操作 | 文件数 | 预计耗时 |
|------|--------|----------|
| 文件存在性检查 | 45 个文件 | ~10ms |
| 版本读取 | 10 个 DLL | ~100ms |
| SHA256 计算 | 45 个文件 (60MB) | ~1200ms |
| 报告生成 | - | ~50ms |
| **总计** | - | **~1.4s** ✅ |

### 4.3 性能优化建议

1. **并行哈希计算**：使用 `rayon` 并行计算多个文件的哈希值
2. **缓存结果**：缓存已验证文件的结果，避免重复计算
3. **增量验证**：仅验证修改过的文件

---

## 五、实现步骤

### Phase 1: 哈希清单生成（构建时）

**时间估计**: 2-3 小时

- [ ] 创建 `libs/portable/build.rs`
- [ ] 实现 SHA256 哈希计算
- [ ] 生成 `checksums.txt` 文件
- [ ] 修改 `build.ps1`，在 Task 19 前调用生成逻辑
- [ ] 验证哈希清单正确嵌入到 portable 包
- [ ] 测试不同文件数量下的生成性能

**验收标准**:
- ✅ 构建时自动生成 `checksums.txt`
- ✅ 哈希清单包含所有关键文件
- ✅ 清单格式符合设计规范

### Phase 2: 快速检查（启动时）

**时间估计**: 3-4 小时

- [ ] 创建 `libs/portable/src/quick_check.rs`
- [ ] 实现文件存在性检查
- [ ] 实现版本读取（Windows PE）
- [ ] 实现文件大小合理性检查
- [ ] 在 `main.rs` 解压完成后调用快速检查
- [ ] 添加详细日志输出
- [ ] 性能测试，确保 < 50ms

**验收标准**:
- ✅ 快速检查总耗时 < 50ms
- ✅ 检测到关键文件缺失时输出错误
- ✅ 检测到版本不匹配时输出警告

### Phase 3: 完整验证（CLI）

**时间估计**: 5-6 小时

- [ ] 创建 `src/portable_verify/` 模块结构
- [ ] 实现 `hash.rs`（SHA256/SHA1/MD5）
- [ ] 实现 `version.rs`（PE 文件版本读取）
- [ ] 实现 `checksums.rs`（清单解析）
- [ ] 实现 `verify.rs`（验证主逻辑）
- [ ] 实现 `report.rs`（文本/JSON 输出）
- [ ] 在 `src/core_main.rs` 添加 CLI 命令
- [ ] 添加 `Cargo.toml` 依赖（sha2, sha1, md-5, serde_json）

**验收标准**:
- ✅ CLI 命令正常工作
- ✅ 支持所有哈希算法
- ✅ 支持文本和 JSON 输出
- ✅ 完整验证总耗时 < 2s

### Phase 4: 文档和测试

**时间估计**: 2-3 小时

- [ ] 更新 `src/cli_help.rs`，添加 `--verify-portable` 帮助
- [ ] 编写单元测试
  - [ ] 哈希计算测试
  - [ ] 版本读取测试
  - [ ] 快速检查测试
- [ ] 编写集成测试
  - [ ] 完整验证流程测试
  - [ ] 错误场景测试
- [ ] 更新用户文档（README）

**验收标准**:
- ✅ 测试覆盖率 > 80%
- ✅ 所有测试通过
- ✅ 文档完整且准确

---

## 六、CLI 使用示例

### 6.1 基本使用

```bash
# 验证当前目录
rustdesk.exe --verify-portable

# 验证指定目录
rustdesk.exe --verify-portable C:\path\to\portable

# 使用 SHA1（更快）
rustdesk.exe --verify-portable --hash-algorithm sha1

# 使用 MD5（最快）
rustdesk.exe --verify-portable --hash-algorithm md5

# 跳过哈希验证（仅检查版本和存在性）
rustdesk.exe --verify-portable --skip-hash

# JSON 输出（用于自动化）
rustdesk.exe --verify-portable --json > report.json

# 组合使用
rustdesk.exe --verify-portable --hash-algorithm sha256 --json C:\portable
```

### 6.2 输出格式对比

#### 文本格式（人类可读）

```
RustDesk Portable Verification Report
========================================
Portable Directory: C:\path\to\portable
Expected Version: 1.4.3-jc12
Hash Algorithm: SHA256

Verifying files...
  ✓ rustdesk.exe
    Version: 1.4.3-jc12 (OK)
    SHA256:  a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6... (OK)
    Size:    15.2 MB

  ✓ libsciter.dll
    Version: 4.4.8.30 (OK)
    SHA256:  e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0... (OK)
    Size:    8.5 MB

  ✗ WindowInjection.dll
    Version: 1.0.0.0 (expected: 1.0.1.0) [WARNING]
    SHA256:  i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4... (MISMATCH) [ERROR]
    Expected: m3n4o5p6q7r8s9t0u1v2w3x4y5z6a7b8...
    Size:    156 KB

Summary:
========================================
  Total files: 45
  Passed: 42
  Warnings: 1 (version mismatch)
  Errors: 2 (hash mismatch + missing file)
  Total size: 58.3 MB
  Verification time: 2.34s

Status: FAILED ✗
```

#### JSON 格式（机器可读）

```json
{
  "portable_dir": "C:\\path\\to\\portable",
  "expected_version": "1.4.3-jc12",
  "files": [
    {
      "file_path": "rustdesk.exe",
      "file_type": "Critical",
      "checks": {
        "exists": {
          "status": "Ok",
          "message": null
        },
        "size": {
          "actual_size": 15925248,
          "expected_size": null,
          "status": "Ok"
        },
        "version": {
          "actual_version": "1.4.3-jc12",
          "expected_version": "1.4.3-jc12",
          "status": "Ok"
        },
        "hash": {
          "algorithm": "SHA256",
          "actual_hash": "a1b2c3d4e5f6g7h8...",
          "expected_hash": "a1b2c3d4e5f6g7h8...",
          "status": "Ok",
          "compute_time_ms": 234
        }
      }
    },
    {
      "file_path": "WindowInjection.dll",
      "file_type": "Optional",
      "checks": {
        "exists": {
          "status": "Ok",
          "message": null
        },
        "size": {
          "actual_size": 159744,
          "expected_size": null,
          "status": "Ok"
        },
        "version": {
          "actual_version": "1.0.0.0",
          "expected_version": "1.0.1.0",
          "status": "Warning"
        },
        "hash": {
          "algorithm": "SHA256",
          "actual_hash": "i9j0k1l2m3n4o5p6...",
          "expected_hash": "m3n4o5p6q7r8s9t0...",
          "status": "Error",
          "compute_time_ms": 12
        }
      }
    }
  ],
  "summary": {
    "total": 45,
    "passed": 42,
    "warnings": 1,
    "errors": 2,
    "overall_status": false
  },
  "elapsed_secs": 2.34
}
```

### 6.3 退出码

```
0  - 验证成功，所有检查通过
1  - 验证失败，存在错误或警告
2  - 参数错误或配置错误
```

### 6.4 自动化脚本示例

```powershell
# PowerShell 自动化验证脚本
$result = & rustdesk.exe --verify-portable --json | ConvertFrom-Json

if ($result.summary.overall_status -eq $true) {
    Write-Host "✓ Verification passed" -ForegroundColor Green
    exit 0
} else {
    Write-Host "✗ Verification failed" -ForegroundColor Red
    Write-Host "  Errors: $($result.summary.errors)" -ForegroundColor Red
    Write-Host "  Warnings: $($result.summary.warnings)" -ForegroundColor Yellow
    exit 1
}
```

---

## 七、安全考虑

### 7.1 哈希算法安全性

- **SHA256**：推荐用于生产环境，提供最高安全性
- **SHA1**：适用于快速验证，安全性中等
- **MD5**：仅用于兼容性测试，不推荐用于安全验证

### 7.2 文件完整性保护

- 哈希清单 `checksums.txt` 应在构建时生成并签名
- 防止恶意篡改哈希清单本身
- 考虑使用数字签名验证 portable 包的完整性

### 7.3 性能与安全的平衡

- 启动时使用快速检查（无哈希）以保证性能
- CLI 工具提供完整哈希验证用于安全诊断
- 用户可根据需求选择合适的验证级别

---

## 八、未来优化方向

### 8.1 增量验证

仅验证修改过的文件，提高验证速度：
- 记录上次验证时间
- 对比文件修改时间
- 跳过未修改的文件

### 8.2 并行哈希计算

使用多线程并行计算哈希值：
```rust
use rayon::prelude::*;

let results: Vec<_> = files.par_iter()
    .map(|file| compute_file_hash(file, algo))
    .collect();
```

### 8.3 缓存机制

缓存验证结果，避免重复计算：
```rust
// .cache/verification_cache.json
{
  "rustdesk.exe": {
    "last_verified": "2025-01-21T12:34:56Z",
    "hash": "a1b2c3d4...",
    "status": "Ok"
  }
}
```

### 8.4 网络验证

从官方服务器下载最新的哈希清单，验证本地文件：
```rust
let official_checksums = download_checksums(
    "https://rustdesk.com/portable/checksums/1.4.3-jc12.txt"
)?;
```

---

## 九、总结

本设计方案提供了一个完整的 Windows Portable 版本验证解决方案，包括：

1. **双模式验证**：
   - 启动时的快速检查（< 50ms）
   - CLI 的完整验证（< 2s）

2. **多层次检查**：
   - 文件存在性
   - 文件大小
   - PE 文件版本
   - 哈希完整性（SHA256/SHA1/MD5）

3. **灵活的输出**：
   - 人类可读的文本格式
   - 机器可读的 JSON 格式

4. **性能优化**：
   - 针对不同场景选择合适的验证级别
   - 使用高效的哈希算法和缓冲策略

该方案在保证验证准确性的同时，充分考虑了性能影响，适合在生产环境中使用。

---

**文档结束**
