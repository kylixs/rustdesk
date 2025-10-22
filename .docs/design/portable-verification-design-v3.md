# Windows Portable 验证功能设计方案 v3（最终版）

**文档版本**: 3.0
**创建日期**: 2025-01-22
**最后更新**: 2025-01-22
**状态**: 待实现

## 版本变更

### v3.0 (2025-01-22)
- ✅ **核心变更**: 复用 portable 现有的 data.bin 打包机制
- ✅ **简化方案**: checksums.bin 作为普通文件打包，无需 PE 资源节
- ✅ **提取机制**: 扩展 BinaryReader，支持提取指定文件
- ✅ **详细输出**: 包含期望 MD5 vs 实际 MD5 对比
- ✅ **分离展示**: 列表概要 + 详细明细两部分

### v2.0 对比
- ❌ v2: 使用 Windows PE 资源节 (.rsrc) 嵌入（复杂）
- ✅ v3: 复用现有 data.bin 打包机制（简单）

---

## 目录

- [一、核心设计](#一核心设计)
- [二、数据格式设计](#二数据格式设计)
- [三、实现流程](#三实现流程)
- [四、CLI 使用](#四-cli-使用)
- [五、实现任务](#五实现任务)

---

## 一、核心设计

### 1.1 核心思路

**问题**: 如何验证 portable 解压后的文件完整性？

**方案**:
1. **构建时**: 生成 `checksums.bin`（二进制格式），包含所有文件的 MD5
2. **打包时**: 将 `checksums.bin` 通过现有的 `generate.py` 打包进 `data.bin`
3. **运行时**: 从 portable packer 提取 `checksums.bin`，验证解压目录

### 1.2 架构图

```
构建阶段:
┌─────────────────┐
│ Source Directory│  (rustdesk.exe, *.dll, etc.)
└────────┬────────┘
         │
         ├─> generate.py --folder (原有流程)
         │   ├─> 压缩所有文件 (Brotli)
         │   ├─> 计算 MD5
         │   └─> 生成 data.bin
         │
         └─> build.rs (新增)
             ├─> 读取 PORTABLE_SOURCE_DIR
             ├─> 计算所有文件 MD5
             └─> 生成 checksums.bin (RDCK 格式)

打包阶段:
┌─────────────────┐
│  checksums.bin  │ (在 source directory 中)
└────────┬────────┘
         │
         └─> generate.py 打包进 data.bin (作为普通文件)

运行时验证:
┌──────────────────────┐
│ rustdesk-portable-   │
│ packer.exe           │
│  ├─ data.bin         │  BinaryReader::extract_file("checksums.bin")
│  │   ├─ rustdesk.exe │       │
│  │   ├─ *.dll        │       │
│  │   └─ checksums.bin│◄──────┘
│  └─ (code)           │
└──────────────────────┘
         │
         └─> rustdesk.exe --verify-portable
             ├─> 提取 checksums.bin
             ├─> 解析 RDCK 格式
             ├─> 遍历解压目录
             ├─> 计算实际 MD5
             └─> 对比并输出（仅失败文件 + 详细 MD5）
```

### 1.3 核心优势

1. **复用现有机制**: 无需开发 PE 资源节嵌入/提取逻辑
2. **双重校验**:
   - data.bin 自带 MD5（粗粒度，整包校验）
   - checksums.bin（细粒度，文件级校验）
3. **独立提取**: BinaryReader 可单独提取任意文件
4. **详细诊断**: 输出期望 MD5 vs 实际 MD5，便于排查问题

---

## 二、数据格式设计

### 2.1 checksums.bin 二进制格式

**Magic Number**: `RDCK` (RustDesk ChecKsum)

**格式规范**:

```
Offset | Size | Field          | Description
-------|------|----------------|----------------------------------
0x00   | 4    | Magic          | "RDCK" (0x52 0x44 0x43 0x4B)
0x04   | 2    | Version        | u16 LE, 当前版本 = 1
0x06   | 1    | Algorithm      | u8: 1=MD5, 2=SHA1, 3=SHA256
0x07   | 4    | Reserved       | 保留字段，填充 0x00
0x0B   | 4    | File Count     | u32 LE, 文件数量
-------|------|----------------|----------------------------------
       |      | Entry[0]       |
0x0F   | 2    | Path Length    | u16 LE
0x11   | N    | Path           | UTF-8 字符串
       | 16   | Hash           | MD5 hash (16 bytes)
-------|------|----------------|----------------------------------
       |      | Entry[1]       | (重复)
       | ...  | ...            |
-------|------|----------------|----------------------------------
```

**大小估算** (45 个文件):
- Header: 15 bytes
- 每个文件: 2 (len) + ~20 (平均路径) + 16 (MD5) = ~38 bytes
- 总计: 15 + 45 × 38 ≈ **1.7 KB** (未压缩)
- Brotli 压缩后: ~1.2 KB

### 2.2 Rust 数据结构

```rust
// libs/portable/src/checksum.rs

pub const MAGIC: &[u8; 4] = b"RDCK";
pub const VERSION: u16 = 1;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum HashAlgorithm {
    MD5 = 1,
    SHA1 = 2,
    SHA256 = 3,
}

#[derive(Debug, Clone)]
pub struct ChecksumDb {
    pub algorithm: HashAlgorithm,
    pub checksums: HashMap<String, Vec<u8>>,
}

impl ChecksumDb {
    pub fn serialize(&self) -> Vec<u8>;
    pub fn deserialize(data: &[u8]) -> io::Result<Self>;
    pub fn get(&self, path: &str) -> Option<&[u8]>;
}
```

---

## 三、实现流程

### 3.1 构建时生成 checksums.bin

**文件**: `libs/portable/build.rs`

```rust
fn main() {
    // 如果设置了 PORTABLE_SOURCE_DIR，生成 checksums.bin
    if let Ok(source_dir) = std::env::var("PORTABLE_SOURCE_DIR") {
        let source_path = Path::new(&source_dir);
        if source_path.exists() {
            // 生成 checksums.bin 到 source_dir/.rustdesk/checksums.bin
            let output = source_path.join(".rustdesk").join("checksums.bin");
            generate_checksums_binary(&source_dir, &output)?;
        }
    } else {
        // 创建空 checksums.bin（避免编译错误）
        create_empty_checksums("checksums.bin")?;
    }
}
```

**关键**: 将 `checksums.bin` 生成到 **source directory** 内，这样 `generate.py` 会自动打包它。

### 3.2 打包进 data.bin

**文件**: `libs/portable/generate.py`

**无需修改**，现有逻辑已足够：

```python
# generate.py 会自动遍历所有文件
def generate_md5_table(folder: str, level) -> dict:
    for root, _, files in os.walk('.'):
        for f in files:
            # 包括 .rustdesk/checksums.bin
            ...
```

**构建命令**:
```bash
# 1. 设置环境变量（触发 checksums.bin 生成）
export PORTABLE_SOURCE_DIR=/path/to/rustdesk/build/output

# 2. 构建 portable library（生成 checksums.bin）
cd libs/portable
cargo build --release

# 3. 打包（generate.py 会自动包含 checksums.bin）
python3 generate.py -f /path/to/rustdesk/build/output -o . -e rustdesk.exe
```

### 3.3 运行时提取 checksums.bin

**文件**: `libs/portable/src/bin_reader.rs`

新增方法：

```rust
impl BinaryReader {
    /// 提取指定文件的原始数据（解压后）
    pub fn extract_file(&self, path: &str) -> Option<Vec<u8>> {
        for file in &self.files {
            if file.path == path {
                return Some(file.decompress());
            }
        }
        None
    }

    /// 从 portable packer 可执行文件中提取文件
    pub fn extract_from_exe(exe_path: &Path, file_path: &str) -> Option<Vec<u8>> {
        // 1. 读取 exe 中的 BIN_DATA
        // 2. 解析 BinaryReader
        // 3. 提取指定文件
        // 注意: 需要从外部 exe 读取，而非 include_bytes!
    }
}
```

### 3.4 验证逻辑

**文件**: `src/portable_verify.rs` (新建)

```rust
pub fn verify_portable_directory(dir: &Path) -> VerifyResult {
    // 1. 定位 portable packer 可执行文件
    let packer_path = find_portable_packer()?;

    // 2. 从 packer 提取 checksums.bin
    let checksums_data = BinaryReader::extract_from_exe(&packer_path, ".rustdesk/checksums.bin")?;

    // 3. 解析 checksums.bin
    let checksum_db = ChecksumDb::deserialize(&checksums_data)?;

    // 4. 遍历目录，验证每个文件
    let mut failures = Vec::new();
    for (rel_path, expected_hash) in &checksum_db.checksums {
        let file_path = dir.join(rel_path);

        match verify_file(&file_path, expected_hash) {
            Ok(actual_hash) if actual_hash == expected_hash => {
                // 通过
            }
            Ok(actual_hash) => {
                failures.push(FileFailure {
                    path: rel_path.clone(),
                    status: FailureType::HashMismatch,
                    expected_md5: hex::encode(expected_hash),
                    actual_md5: Some(hex::encode(actual_hash)),
                    file_size: get_file_size(&file_path),
                });
            }
            Err(_) => {
                failures.push(FileFailure {
                    path: rel_path.clone(),
                    status: FailureType::Missing,
                    expected_md5: hex::encode(expected_hash),
                    actual_md5: None,
                    file_size: None,
                });
            }
        }
    }

    VerifyResult { failures, ... }
}
```

---

## 四、CLI 使用

### 4.1 命令格式

```bash
# 验证当前 --server 解压目录（自动定位）
rustdesk.exe --verify-portable

# 验证指定目录
rustdesk.exe --verify-portable C:\path\to\extracted

# 快速状态查看（仅检查存在性，不验证哈希）
rustdesk.exe --verify-portable --status

# JSON 输出
rustdesk.exe --verify-portable --json
```

### 4.2 输出格式

#### 成功时

```
RustDesk Portable Verification Report
================================================================================
Directory: C:\Users\user\AppData\Local\Temp\rustdesk
Hash Algorithm: MD5
Checksum Source: Embedded in portable packer

✓ All files verified successfully

Summary:
  Total: 45 files, 58.3 MB
  Passed: 45 files (100%)
  Status: OK ✓
  Verification Time: 1.23s
```

#### 失败时（列表概要 + 详细明细）

```
RustDesk Portable Verification Report
================================================================================
Directory: C:\Users\user\AppData\Local\Temp\rustdesk
Hash Algorithm: MD5
Checksum Source: Embedded in portable packer

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

#### --status 模式（快速概要）

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

## 五、实现任务

### Phase 1: Checksum 格式实现 ✅
- [x] 创建 `libs/portable/src/checksum.rs`
- [x] 实现 `ChecksumDb` 序列化/反序列化
- [x] 单元测试（空数据、有数据、错误格式）

### Phase 2: 构建时生成
- [ ] 修改 `libs/portable/build.rs`
  - [ ] 读取 `PORTABLE_SOURCE_DIR` 环境变量
  - [ ] 遍历源目录计算 MD5
  - [ ] 生成 `checksums.bin` 到 `$SOURCE_DIR/.rustdesk/checksums.bin`
  - [ ] 无环境变量时生成空文件
- [ ] 测试: 设置环境变量后 `cargo build`

### Phase 3: 提取机制
- [ ] 扩展 `libs/portable/src/bin_reader.rs`
  - [ ] 添加 `extract_file(&self, path)` 方法
  - [ ] 添加 `extract_from_exe(exe_path, file_path)` 静态方法
  - [ ] 处理从外部 exe 读取 data.bin
- [ ] 测试: 从 portable packer 提取 checksums.bin

### Phase 4: 验证逻辑
- [ ] 创建 `src/portable_verify/mod.rs`
  - [ ] `verify_portable_directory(dir)` 主函数
  - [ ] `find_portable_packer()` 定位 packer
  - [ ] `verify_file(path, expected_hash)` 单文件验证
  - [ ] `VerifyResult` 结构体（失败列表）
- [ ] 创建 `src/portable_verify/output.rs`
  - [ ] 表格格式输出（Unicode box-drawing）
  - [ ] 详细明细输出（期望 MD5 vs 实际 MD5）
  - [ ] JSON 格式输出
  - [ ] --status 快速模式

### Phase 5: CLI 集成
- [ ] 修改 `src/main.rs`
  - [ ] 添加 `--verify-portable [DIR]` 参数
  - [ ] 添加 `--status` 参数
  - [ ] 添加 `--json` 参数
  - [ ] 调用验证逻辑并格式化输出

### Phase 6: 测试与文档
- [ ] 端到端测试
  - [ ] 正常场景（所有文件完整）
  - [ ] 文件缺失场景
  - [ ] 文件被篡改场景（MD5 不匹配）
- [ ] 更新构建文档
- [ ] 更新用户手册

---

## 六、时间估算

| Phase | 任务 | 预计时间 |
|-------|------|---------|
| 1 | Checksum 格式 | ✅ 已完成 |
| 2 | 构建时生成 | 1-2 小时 |
| 3 | 提取机制 | 2-3 小时 |
| 4 | 验证逻辑 | 3-4 小时 |
| 5 | CLI 集成 | 1-2 小时 |
| 6 | 测试与文档 | 2-3 小时 |
| **总计** | | **10-15 小时** |

---

## 七、关键技术点

### 7.1 从外部 exe 读取 data.bin

**挑战**: `BIN_DATA` 使用 `include_bytes!` 编译时嵌入，无法从外部 exe 读取。

**方案**: 手动解析 PE 格式，或简单方案：

```rust
// 方案 A: 假设 data.bin 在已知偏移量（需要定位魔数）
pub fn extract_from_exe(exe_path: &Path, file_path: &str) -> Option<Vec<u8>> {
    let exe_data = std::fs::read(exe_path).ok()?;

    // 搜索 "rustdesk" magic number
    let magic = b"rustdesk";
    let start = exe_data.windows(8).position(|w| w == magic)?;

    // 从 start 开始解析 BinaryReader 格式
    let reader = BinaryReader::parse_from_bytes(&exe_data[start..])?;
    reader.extract_file(file_path)
}

// 方案 B: 直接运行 packer 并捕获输出的 checksums.bin
```

### 7.2 定位 portable packer

```rust
fn find_portable_packer() -> Option<PathBuf> {
    // 方法 1: 检查当前目录
    let current_exe = std::env::current_exe().ok()?;
    if let Some(dir) = current_exe.parent() {
        let packer = dir.join("rustdesk-portable-packer.exe");
        if packer.exists() {
            return Some(packer);
        }
    }

    // 方法 2: 环境变量
    if let Ok(path) = std::env::var("RUSTDESK_PORTABLE_PACKER") {
        let p = PathBuf::from(path);
        if p.exists() {
            return Some(p);
        }
    }

    None
}
```

---

## 八、FAQ

### Q1: 为什么不直接在 rustdesk.exe 中嵌入 checksums.bin？

**A**:
- portable packer 已经有完整的打包机制
- 避免重复逻辑
- checksums.bin 需要在 packer 构建时生成，此时 rustdesk.exe 已经编译完成

### Q2: checksums.bin 会被双重压缩吗？

**A**: 是的，checksums.bin 本身已经很小（~1.7KB），generate.py 会再次 Brotli 压缩，但由于数据已经很紧凑，压缩率有限（~30%）。总体影响可忽略。

### Q3: 如果 checksums.bin 被篡改怎么办？

**A**: data.bin 中的 checksums.bin 有独立的 MD5 校验。如果 checksums.bin 被修改，BinaryReader 会检测到 MD5 不匹配并拒绝解压。

### Q4: 输出格式中的 "期望 MD5 vs 实际 MD5" 如何实现？

**A**:
```rust
struct FileFailure {
    path: String,
    status: FailureType,
    expected_md5: String,  // hex 编码
    actual_md5: Option<String>,  // None = 文件缺失
    expected_size: Option<u64>,
    actual_size: Option<u64>,
}
```

---

## 九、后续优化

1. **性能优化**: 并行计算 MD5（rayon）
2. **增量验证**: 仅验证修改时间变化的文件
3. **自动修复**: `--verify-portable --fix` 自动重新解压损坏文件
4. **签名验证**: 除 MD5 外，增加数字签名验证
