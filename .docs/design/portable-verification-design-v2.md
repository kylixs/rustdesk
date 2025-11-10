# Windows Portable 验证功能设计方案 v2

**文档版本**: 2.0
**创建日期**: 2025-01-22
**最后更新**: 2025-01-22
**状态**: 实现阶段

## 版本变更

### v2.0 (2025-01-22)
- ✅ **核心变更**: Checksum 数据以二进制形式嵌入 portable 程序数据段
- ✅ **优化**: 验证时从 portable 程序自身提取 checksum
- ✅ **优化**: 默认使用 MD5 算法（性能优先）
- ✅ **优化**: 输出仅显示验证失败的文件
- ✅ **优化**: 表格格式，每个文件一行

---

## 目录

- [一、核心设计](#一核心设计)
- [二、数据格式设计](#二数据格式设计)
- [三、实现流程](#三实现流程)
- [四、CLI 使用](#四-cli-使用)

---

## 一、核心设计

### 1.1 核心思路

**问题**: 如何将 checksum 清单嵌入到 portable 程序，又不污染代码？

**方案**: 使用 Windows PE 资源段 (Resource Section) 存储 checksum 数据

```
┌────────────────────────────────────┐
│   rustdesk-portable-packer.exe    │
├────────────────────────────────────┤
│  .text  (代码段)                   │
│  .data  (数据段)                   │
│  .rsrc  (资源段) ← checksum 在这里 │
│  ...                               │
└────────────────────────────────────┘
```

**优点**:
- ✅ 不污染代码，保持代码整洁
- ✅ 标准 PE 格式，Windows 原生支持
- ✅ 可使用 Rust winapi 轻松读取
- ✅ 二进制格式，体积小且解析快

### 1.2 工作流程

```
┌─────────────────────────────────────────────────────────────┐
│  构建时 (build.ps1)                                         │
├─────────────────────────────────────────────────────────────┤
│  1. 解压 portable 包到临时目录                              │
│  2. 遍历所有文件，计算 MD5                                  │
│  3. 生成 checksums.bin (二进制格式)                         │
│  4. 使用 ResourceHacker 将 checksums.bin 嵌入 .exe        │
│     或在编译时通过 winres 嵌入                              │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  验证时 (rustdesk.exe --verify-portable)                    │
├─────────────────────────────────────────────────────────────┤
│  1. 定位 portable packer 程序                               │
│  2. 从 .rsrc 段读取 checksums.bin                          │
│  3. 反序列化为 HashMap<String, [u8; 16]>                   │
│  4. 遍历 --server 解压目录                                  │
│  5. 计算每个文件的 MD5                                      │
│  6. 对比 checksum                                           │
│  7. 输出验证失败的文件（表格格式）                          │
└─────────────────────────────────────────────────────────────┘
```

---

## 二、数据格式设计

### 2.1 二进制格式 (checksums.bin)

使用紧凑的二进制格式存储：

```
┌──────────────────────────────────────────┐
│  Magic Number (4 bytes): "RDCK"          │  验证文件格式
├──────────────────────────────────────────┤
│  Version (2 bytes): 0x0001               │  格式版本
├──────────────────────────────────────────┤
│  Hash Algorithm (1 byte): 0x01 (MD5)    │  哈希算法
├──────────────────────────────────────────┤
│  File Count (4 bytes): little-endian     │  文件数量
├──────────────────────────────────────────┤
│  [File Entry 1]                          │
│    Path Length (2 bytes)                 │  路径长度
│    Path (UTF-8 bytes)                    │  相对路径
│    Hash (16 bytes for MD5)               │  文件哈希
├──────────────────────────────────────────┤
│  [File Entry 2]                          │
│    ...                                   │
├──────────────────────────────────────────┤
│  ...                                     │
└──────────────────────────────────────────┘
```

**总大小估算** (45 个文件，平均路径 30 字节):
```
Header: 11 bytes
Entries: 45 * (2 + 30 + 16) = 2,160 bytes
Total: ~2.1 KB  ✅ (非常紧凑)
```

对比文本格式 (checksums.txt):
```
每行: 32 (MD5 hex) + 2 (spaces) + 30 (path) + 1 (newline) = 65 bytes
45 files: 65 * 45 = 2,925 bytes
Text Total: ~2.9 KB

节省: 27% 空间  ✅
```

### 2.2 Rust 数据结构

```rust
// libs/portable/src/checksum.rs

use std::collections::HashMap;

/// Checksum binary format header
#[repr(C, packed)]
struct ChecksumHeader {
    magic: [u8; 4],        // "RDCK"
    version: u16,          // 0x0001
    algorithm: u8,         // 0x01 = MD5
    file_count: u32,       // Number of files
}

/// Hash algorithm enum
#[derive(Debug, Clone, Copy, PartialEq)]
#[repr(u8)]
pub enum HashAlgorithm {
    Md5 = 0x01,
    Sha256 = 0x02,
    Sha1 = 0x03,
}

/// Checksum database
pub struct ChecksumDb {
    pub algorithm: HashAlgorithm,
    pub checksums: HashMap<String, Vec<u8>>,
}

impl ChecksumDb {
    /// Serialize to binary format
    pub fn serialize(&self) -> Vec<u8> {
        let mut data = Vec::new();

        // Header
        data.extend_from_slice(b"RDCK");
        data.extend_from_slice(&1u16.to_le_bytes());
        data.push(self.algorithm as u8);
        data.extend_from_slice(&(self.checksums.len() as u32).to_le_bytes());

        // Entries
        for (path, hash) in &self.checksums {
            let path_bytes = path.as_bytes();
            data.extend_from_slice(&(path_bytes.len() as u16).to_le_bytes());
            data.extend_from_slice(path_bytes);
            data.extend_from_slice(hash);
        }

        data
    }

    /// Deserialize from binary format
    pub fn deserialize(data: &[u8]) -> Result<Self, String> {
        if data.len() < 11 {
            return Err("Data too short".to_string());
        }

        // Verify magic
        if &data[0..4] != b"RDCK" {
            return Err("Invalid magic number".to_string());
        }

        // Read header
        let version = u16::from_le_bytes([data[4], data[5]]);
        if version != 1 {
            return Err(format!("Unsupported version: {}", version));
        }

        let algorithm = match data[6] {
            0x01 => HashAlgorithm::Md5,
            0x02 => HashAlgorithm::Sha256,
            0x03 => HashAlgorithm::Sha1,
            _ => return Err("Unknown algorithm".to_string()),
        };

        let file_count = u32::from_le_bytes([data[7], data[8], data[9], data[10]]);

        // Read entries
        let mut checksums = HashMap::new();
        let mut offset = 11;
        let hash_size = match algorithm {
            HashAlgorithm::Md5 => 16,
            HashAlgorithm::Sha256 => 32,
            HashAlgorithm::Sha1 => 20,
        };

        for _ in 0..file_count {
            if offset + 2 > data.len() {
                return Err("Truncated data".to_string());
            }

            let path_len = u16::from_le_bytes([data[offset], data[offset + 1]]) as usize;
            offset += 2;

            if offset + path_len + hash_size > data.len() {
                return Err("Truncated entry".to_string());
            }

            let path = String::from_utf8(data[offset..offset + path_len].to_vec())
                .map_err(|e| format!("Invalid UTF-8: {}", e))?;
            offset += path_len;

            let hash = data[offset..offset + hash_size].to_vec();
            offset += hash_size;

            checksums.insert(path, hash);
        }

        Ok(ChecksumDb { algorithm, checksums })
    }
}
```

---

## 三、实现流程

### 3.1 构建时生成 (build.rs)

```rust
// libs/portable/build.rs

fn main() {
    // ... existing winres code ...

    if let Ok(source_dir) = std::env::var("PORTABLE_SOURCE_DIR") {
        generate_checksum_resource(&source_dir);
    }
}

fn generate_checksum_resource(source_dir: &str) {
    use portable::checksum::{ChecksumDb, HashAlgorithm};

    // 1. Scan all files and compute MD5
    let mut db = ChecksumDb {
        algorithm: HashAlgorithm::Md5,
        checksums: HashMap::new(),
    };

    collect_checksums(Path::new(source_dir), &mut db);

    // 2. Serialize to binary
    let binary_data = db.serialize();

    // 3. Write to checksums.bin
    fs::write("checksums.bin", binary_data).unwrap();

    // 4. Embed as resource using winres
    // This will be added to .rsrc section
    println!("cargo:rerun-if-changed=checksums.bin");
}
```

### 3.2 嵌入资源段 (build.rs)

**方案 A: 使用 winres crate (推荐)**

```rust
// libs/portable/build.rs

#[cfg(windows)]
{
    let mut res = winres::WindowsResource::new();
    res.set_icon("../../res/icon.ico")
        .set_manifest_file("../../res/manifest.xml");

    // 嵌入 checksums.bin 作为自定义资源
    // Resource Type: "CHECKSUMS" (自定义类型)
    // Resource Name: 1
    res.set("CHECKSUMS", "1", "checksums.bin");

    res.compile().unwrap();
}
```

**方案 B: 使用 .rc 文件**

```rc
// libs/portable/resources.rc
1 CHECKSUMS "checksums.bin"
```

```rust
// libs/portable/build.rs
embed_resource::compile("resources.rc");
```

**依赖**:
```toml
[build-dependencies]
embed-resource = "2.4"
```

### 3.3 运行时读取 (rustdesk/src)

```rust
// src/portable_verify/resource.rs

use winapi::um::libloaderapi::{FindResourceW, LoadResource, SizeofResource, LoadLibraryW, FreeLibrary};
use winapi::um::winnt::HMODULE;
use std::ffi::OsStr;
use std::os::windows::ffi::OsStrExt;

/// Extract checksums.bin from portable packer executable
pub fn extract_checksums_from_portable(packer_path: &Path) -> Result<Vec<u8>, String> {
    unsafe {
        // 1. Load portable packer as resource-only module
        let path_wide: Vec<u16> = OsStr::new(packer_path)
            .encode_wide()
            .chain(std::iter::once(0))
            .collect();

        let hmodule = LoadLibraryW(path_wide.as_ptr());
        if hmodule.is_null() {
            return Err("Failed to load portable packer".to_string());
        }

        // 2. Find CHECKSUMS resource
        let resource_type: Vec<u16> = OsStr::new("CHECKSUMS")
            .encode_wide()
            .chain(std::iter::once(0))
            .collect();

        let resource_name: Vec<u16> = vec!['1' as u16, 0];

        let hres = FindResourceW(hmodule, resource_name.as_ptr(), resource_type.as_ptr());
        if hres.is_null() {
            FreeLibrary(hmodule);
            return Err("CHECKSUMS resource not found".to_string());
        }

        // 3. Load resource data
        let hglob = LoadResource(hmodule, hres);
        if hglob.is_null() {
            FreeLibrary(hmodule);
            return Err("Failed to load resource".to_string());
        }

        let size = SizeofResource(hmodule, hres) as usize;
        let ptr = hglob as *const u8;

        // 4. Copy data
        let data = std::slice::from_raw_parts(ptr, size).to_vec();

        FreeLibrary(hmodule);
        Ok(data)
    }
}

/// Find portable packer executable
pub fn find_portable_packer() -> Option<PathBuf> {
    // Method 1: Check current exe directory
    if let Ok(exe_path) = std::env::current_exe() {
        if let Some(dir) = exe_path.parent() {
            let packer = dir.join("rustdesk-portable-packer.exe");
            if packer.exists() {
                return Some(packer);
            }
        }
    }

    // Method 2: Check environment variable
    if let Ok(packer_path) = std::env::var("RUSTDESK_PORTABLE_PACKER") {
        let path = PathBuf::from(packer_path);
        if path.exists() {
            return Some(path);
        }
    }

    None
}
```

---

## 四、CLI 使用

### 4.1 命令格式

```bash
# 验证当前 --server 解压目录
rustdesk.exe --verify-portable

# 验证指定目录
rustdesk.exe --verify-portable C:\path\to\extracted

# 快速状态查看（仅检查存在性和版本，不验证哈希）
rustdesk.exe --verify-portable --status

# JSON 输出
rustdesk.exe --verify-portable --json

# 使用不同哈希算法（如果 checksum 数据支持）
rustdesk.exe --verify-portable --hash-algorithm sha256
```

### 4.2 输出格式（仅失败文件）

**成功时**:
```
RustDesk Portable Verification Report
================================================================================
Directory: C:\Users\user\AppData\Local\Temp\rustdesk
Hash Algorithm: MD5 (from embedded checksums)

✓ All files verified successfully

Summary:
  Total: 45 files, 58.3 MB
  Passed: 45 files (100%)
  Status: OK ✓
  Verification Time: 1.23s
```

**失败时（列表概要 + 详细明细）**:
```
RustDesk Portable Verification Report
================================================================================
Directory: C:\Users\user\AppData\Local\Temp\rustdesk
Hash Algorithm: MD5 (from embedded checksums)

Failed Files (3):
┌──────────────────────────────┬────────┬───────────────────────────┬─────────┐
│ File                         │ Status │ Issue                     │ Size    │
├──────────────────────────────┼────────┼───────────────────────────┼─────────┤
│ WindowInjection.dll          │ ERROR  │ MD5 mismatch              │ 156 KB  │
│ printer_driver_adapter.dll   │ ERROR  │ Missing file              │ -       │
│ libsciter.dll                │ WARN   │ Size differs (8.5→8.6 MB) │ 8.6 MB  │
└──────────────────────────────┴────────┴───────────────────────────┴─────────┘

Detailed Information:
────────────────────────────────────────────────────────────────────────────────
[1] WindowInjection.dll
    Status: ERROR - MD5 hash mismatch
    Path: libs/WindowInjection.dll
    Expected MD5: a3f5c8b2d1e4f6a7b8c9d0e1f2a3b4c5
    Actual MD5:   b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9
    File Size: 156,789 bytes

[2] printer_driver_adapter.dll
    Status: ERROR - File missing
    Path: libs/printer_driver_adapter.dll
    Expected MD5: 1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d
    File Size: N/A

[3] libsciter.dll
    Status: WARNING - File size changed but hash matches
    Path: libs/libsciter.dll
    Expected MD5: 9f8e7d6c5b4a3f2e1d0c9b8a7f6e5d4c
    Actual MD5:   9f8e7d6c5b4a3f2e1d0c9b8a7f6e5d4c (matches)
    Expected Size: 8,912,345 bytes (8.5 MB)
    Actual Size:   9,023,456 bytes (8.6 MB)
────────────────────────────────────────────────────────────────────────────────

Summary:
  Total: 45 files, 58.3 MB
  Passed: 42 files (93.3%)
  Warnings: 1 file
  Errors: 2 files
  Status: FAILED ✗
  Verification Time: 1.23s
```

**--status 模式（快速概要）**:
```
RustDesk Portable Status Check
================================================================================
3 files have issues:

  ✗ WindowInjection.dll - MD5 mismatch
  ✗ printer_driver_adapter.dll - Missing
  ⚠ libsciter.dll - Size mismatch

Status: FAILED (2 errors, 1 warning)
```

---

## 五、实现任务清单

### Phase 1: 数据格式与序列化 (2h)
- [x] 定义二进制格式规范
- [ ] 实现 `ChecksumDb` 序列化/反序列化
- [ ] 单元测试：往返测试 (serialize → deserialize)

### Phase 2: 构建时生成 (2h)
- [ ] 修改 `build.rs` 生成 checksums.bin
- [ ] 使用 winres 嵌入资源段
- [ ] 测试资源是否正确嵌入

### Phase 3: 运行时提取 (3h)
- [ ] 实现从 PE 文件读取资源
- [ ] 实现定位 portable packer 程序
- [ ] 反序列化 checksum 数据

### Phase 4: 验证逻辑 (3h)
- [ ] 遍历 --server 解压目录
- [ ] 计算文件 MD5
- [ ] 对比 checksum
- [ ] 记录失败的文件

### Phase 5: CLI 输出 (2h)
- [ ] 实现表格格式输出
- [ ] 实现 --status 快速模式
- [ ] 实现 JSON 输出
- [ ] 添加帮助文档

---

## 六、技术要点

### 6.1 为什么选择资源段？

| 方案 | 优点 | 缺点 |
|------|------|------|
| **代码嵌入** (`include_str!`) | 简单 | 污染代码，增加二进制体积 |
| **单独文件** | 灵活 | 需要分发两个文件，易丢失 |
| **资源段** ✅ | 标准PE格式，不污染代码，单文件 | 需要 Windows API |
| **附加段** | 自定义 | 非标准，可能被杀毒软件标记 |

### 6.2 安全考虑

1. **Magic Number**: 防止读取错误的资源
2. **Version Field**: 支持格式升级
3. **数据完整性**: 可添加 CRC32 校验和

### 6.3 性能优化

| 操作 | 时间 |
|------|------|
| 从资源段读取 2KB | < 1ms |
| 反序列化 45 个条目 | < 5ms |
| 计算 45 个文件 MD5 (60MB) | ~400ms |
| **总验证时间** | **< 500ms** ✅ |

---

## 七、示例代码整合

### 完整验证流程

```rust
// src/portable_verify/mod.rs

pub fn verify_portable(extract_dir: &Path) -> Result<VerificationReport, String> {
    // 1. 定位 portable packer
    let packer = find_portable_packer()
        .ok_or("Portable packer not found")?;

    // 2. 从资源段读取 checksums
    let checksum_data = extract_checksums_from_portable(&packer)?;
    let checksum_db = ChecksumDb::deserialize(&checksum_data)?;

    // 3. 遍历文件验证
    let mut report = VerificationReport::new(extract_dir);

    for (rel_path, expected_hash) in &checksum_db.checksums {
        let file_path = extract_dir.join(rel_path);

        if !file_path.exists() {
            report.add_error(rel_path, "Missing file");
            continue;
        }

        match compute_file_hash(&file_path, checksum_db.algorithm) {
            Ok(actual_hash) => {
                if &actual_hash != expected_hash {
                    report.add_error(rel_path, "Hash mismatch");
                }
            }
            Err(e) => {
                report.add_error(rel_path, &format!("Hash error: {}", e));
            }
        }
    }

    Ok(report)
}
```

---

**文档结束**
