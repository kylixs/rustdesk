# Portable 验证功能实现任务清单

**基于**: portable-verification-design.md
**创建日期**: 2025-01-22
**优化要求**:
- ✅ 默认使用 MD5 算法（而非 SHA256）
- ✅ 输出仅包含验证失败的文件
- ✅ 每个文件在一行显示（表格格式）
- ✅ `--status` 参数显示差异文件概要

---

## 任务概览

| Phase | 任务 | 预计时间 | 状态 |
|-------|------|----------|------|
| Phase 1 | 哈希清单生成（构建时） | 2-3h | 待开始 |
| Phase 2 | 快速检查（启动时） | 3-4h | 待开始 |
| Phase 3 | 完整验证（CLI） | 5-6h | 待开始 |
| Phase 4 | 优化输出格式 | 2-3h | 待开始 |
| **总计** | | **12-16h** | |

---

## Phase 1: 哈希清单生成（构建时）

### 1.1 创建 build.rs 文件
**文件**: `libs/portable/build.rs`

**任务**:
- [ ] 创建 build.rs 文件
- [ ] 添加依赖：md-5 = "0.10"
- [ ] 实现 `generate_checksums()` 函数
- [ ] 实现 `compute_file_hash()` 函数（MD5）
- [ ] 支持递归目录扫描

**代码框架**:
```rust
// libs/portable/build.rs
use md5::{Md5, Digest};
use std::fs::{self, File};
use std::io::Read;
use std::path::Path;

fn main() {
    // 从环境变量获取源目录
    let source_dir = std::env::var("PORTABLE_SOURCE_DIR")
        .unwrap_or_else(|_| String::from("./rustdesk"));

    // 生成 checksums.txt
    if Path::new(&source_dir).exists() {
        generate_checksums(&source_dir, "checksums.txt").unwrap();
        println!("cargo:rerun-if-changed={}", source_dir);
    }
}

fn generate_checksums(source_dir: &str, output: &str) -> std::io::Result<()> {
    // 生成 MD5 哈希清单
}

fn compute_file_hash(path: &Path) -> std::io::Result<String> {
    // 计算文件 MD5 哈希值
}
```

**验收标准**:
- ✅ 生成的 checksums.txt 包含所有文件
- ✅ 使用 MD5 算法
- ✅ 格式: `<md5_hash>  <file_path>`

---

### 1.2 修改 Cargo.toml
**文件**: `libs/portable/Cargo.toml`

**任务**:
- [ ] 添加 build 依赖：md-5
- [ ] 添加 runtime 依赖：md-5, serde, serde_json

```toml
[build-dependencies]
md-5 = "0.10"

[dependencies]
md-5 = "0.10"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
```

---

### 1.3 嵌入 checksums.txt
**文件**: `libs/portable/src/lib.rs` (新建)

**任务**:
- [ ] 创建 lib.rs
- [ ] 使用 `include_str!` 嵌入 checksums.txt
- [ ] 导出 CHECKSUMS 常量

```rust
// libs/portable/src/lib.rs
pub const CHECKSUMS: &str = include_str!("../checksums.txt");
```

---

## Phase 2: 快速检查（启动时）

### 2.1 创建快速检查模块
**文件**: `libs/portable/src/quick_check.rs`

**任务**:
- [ ] 定义 `QuickChecker` 结构
- [ ] 实现文件存在性检查
- [ ] 实现版本读取（Windows PE）
- [ ] 实现文件大小检查
- [ ] 添加详细日志输出

**关键常量**:
```rust
const CRITICAL_FILES: &[&str] = &[
    "rustdesk.exe",
    "libsciter.dll",
];

const OPTIONAL_FILES: &[&str] = &[
    "WindowInjection.dll",
    "printer_driver_adapter.dll",
];
```

**性能目标**: < 50ms

---

### 2.2 实现版本读取
**文件**: `libs/portable/src/version.rs`

**任务**:
- [ ] 使用 winapi 读取 PE 文件版本
- [ ] 处理 VS_FIXEDFILEINFO 结构
- [ ] 返回格式化的版本字符串

**依赖**:
```toml
[target.'cfg(windows)'.dependencies]
winapi = { version = "0.3", features = ["winver", "verrsrc"] }
```

---

### 2.3 集成到 main.rs
**文件**: `libs/portable/src/main.rs`

**任务**:
- [ ] 导入 quick_check 模块
- [ ] 在解压完成后调用快速检查
- [ ] 输出检查结果日志
- [ ] 不阻止程序启动（仅警告）

```rust
mod quick_check;
use quick_check::QuickChecker;

fn main() {
    // ... 解压逻辑

    log::info!("Running quick verification...");
    let checker = QuickChecker::new(extract_dir.clone(), VERSION);
    let result = checker.verify();

    if !result.is_ok() {
        for error in &result.errors {
            log::error!("{}", error);
        }
    }

    // 继续启动
}
```

---

## Phase 3: 完整验证（CLI）

### 3.1 创建验证模块结构
**目录**: `src/portable_verify/`

**文件列表**:
- [ ] `mod.rs` - 模块入口
- [ ] `verify.rs` - 验证主逻辑
- [ ] `hash.rs` - 哈希计算（MD5/SHA256/SHA1）
- [ ] `checksums.rs` - 哈希清单解析
- [ ] `report.rs` - 结果输出（表格格式）
- [ ] `types.rs` - 数据结构定义

---

### 3.2 实现数据结构
**文件**: `src/portable_verify/types.rs`

**任务**:
- [ ] 定义 `VerificationMode` 枚举
- [ ] 定义 `HashAlgorithm` 枚举（默认 MD5）
- [ ] 定义 `FileVerificationInfo` 结构
- [ ] 定义 `VerificationResult` 结构
- [ ] 实现 Serialize/Deserialize

```rust
#[derive(Debug, Clone, Copy)]
pub enum HashAlgorithm {
    Md5,      // 默认
    Sha256,
    Sha1,
    None,
}

impl Default for HashAlgorithm {
    fn default() -> Self {
        Self::Md5  // 默认使用 MD5
    }
}
```

---

### 3.3 实现哈希计算
**文件**: `src/portable_verify/hash.rs`

**任务**:
- [ ] 实现 `compute_file_hash()` 函数
- [ ] 支持 MD5/SHA256/SHA1
- [ ] 使用 8KB buffer 优化性能
- [ ] 返回小写十六进制字符串

**依赖**:
```toml
[dependencies]
md-5 = "0.10"
sha2 = "0.10"
sha1 = "0.10"
```

---

### 3.4 实现验证逻辑
**文件**: `src/portable_verify/verify.rs`

**任务**:
- [ ] 实现 `FullVerifier` 结构
- [ ] 加载 checksums.txt
- [ ] 遍历文件进行验证
- [ ] 记录失败的文件
- [ ] 生成汇总信息

**关键点**:
- 仅记录验证失败的文件（存在性、哈希不匹配）
- 计算总体统计信息

---

### 3.5 实现 CLI 命令
**文件**: `src/core_main.rs`

**任务**:
- [ ] 添加 `--verify-portable` 命令处理
- [ ] 添加 `--status` 参数（显示差异概要）
- [ ] 支持 `--hash-algorithm` 参数（默认 md5）
- [ ] 支持 `--json` 输出
- [ ] 支持 `--skip-hash` 跳过哈希验证

**命令示例**:
```bash
# 使用默认 MD5 算法
rustdesk.exe --verify-portable

# 显示差异概要
rustdesk.exe --verify-portable --status

# 使用 SHA256
rustdesk.exe --verify-portable --hash-algorithm sha256

# JSON 输出
rustdesk.exe --verify-portable --json
```

---

## Phase 4: 优化输出格式

### 4.1 实现表格输出
**文件**: `src/portable_verify/report.rs`

**任务**:
- [ ] 实现 `print_table_report()` 函数
- [ ] 仅显示验证失败的文件
- [ ] 每个文件一行（表格格式）
- [ ] 显示汇总信息

**输出格式**:
```
RustDesk Portable Verification Report
================================================================================
Directory: C:\path\to\portable
Hash Algorithm: MD5
Total Files: 45

Failed Files:
┌─────────────────────────────┬────────┬──────────────────────────────┬─────────┐
│ File                        │ Status │ Issue                        │ Size    │
├─────────────────────────────┼────────┼──────────────────────────────┼─────────┤
│ WindowInjection.dll         │ ERROR  │ Hash mismatch                │ 156 KB  │
│ printer_driver_adapter.dll  │ ERROR  │ Missing file                 │ -       │
│ rustdesk.exe                │ WARN   │ Version: 1.4.2 (exp: 1.4.3)  │ 15.2 MB │
└─────────────────────────────┴────────┴──────────────────────────────┴─────────┘

Summary:
  Total: 45 files, 58.3 MB
  Passed: 42 files (93.3%)
  Warnings: 1 file (version mismatch)
  Errors: 2 files (hash mismatch, missing)

  Verification Time: 1.23s
  Status: FAILED ✗
```

---

### 4.2 实现 --status 概要输出
**文件**: `src/portable_verify/report.rs`

**任务**:
- [ ] 实现 `print_status_summary()` 函数
- [ ] 仅显示差异文件列表
- [ ] 简洁的单行格式

**输出格式**:
```
RustDesk Portable Status
================================================================================
3 files have issues:

  ✗ WindowInjection.dll - Hash mismatch
  ✗ printer_driver_adapter.dll - Missing
  ⚠ rustdesk.exe - Version mismatch (1.4.2 vs 1.4.3)

Status: FAILED (2 errors, 1 warning)
```

---

### 4.3 实现 JSON 输出
**文件**: `src/portable_verify/report.rs`

**任务**:
- [ ] 实现 `print_json_report()` 函数
- [ ] 仅包含失败的文件
- [ ] 使用 serde_json 序列化

**JSON 格式**:
```json
{
  "status": "failed",
  "summary": {
    "total": 45,
    "passed": 42,
    "warnings": 1,
    "errors": 2
  },
  "failed_files": [
    {
      "path": "WindowInjection.dll",
      "status": "error",
      "issue": "hash_mismatch",
      "expected_hash": "abc123...",
      "actual_hash": "def456...",
      "size": 159744
    },
    {
      "path": "printer_driver_adapter.dll",
      "status": "error",
      "issue": "missing",
      "size": null
    }
  ],
  "verification_time_secs": 1.23
}
```

---

## 实现顺序

### Step 1: 基础设施（2-3h）
1. 创建 `libs/portable/build.rs`
2. 修改 `libs/portable/Cargo.toml`
3. 实现 MD5 哈希清单生成
4. 测试 checksums.txt 生成

### Step 2: 快速检查（3-4h）
1. 创建 `libs/portable/src/quick_check.rs`
2. 实现文件存在性检查
3. 实现版本读取（Windows）
4. 集成到 portable main.rs
5. 性能测试（目标 < 50ms）

### Step 3: CLI 验证核心（3-4h）
1. 创建 `src/portable_verify/` 模块结构
2. 实现数据结构 `types.rs`
3. 实现哈希计算 `hash.rs`
4. 实现验证逻辑 `verify.rs`
5. 解析 checksums.txt

### Step 4: CLI 命令与输出（2-3h）
1. 在 `core_main.rs` 添加命令处理
2. 实现表格输出格式
3. 实现 `--status` 概要输出
4. 实现 JSON 输出
5. 添加帮助文档

### Step 5: 测试与优化（2h）
1. 单元测试
2. 集成测试
3. 性能测试
4. 文档更新

---

## 验收标准

### 功能验收
- ✅ 构建时自动生成 checksums.txt（MD5）
- ✅ Portable 启动时快速检查 < 50ms
- ✅ CLI `--verify-portable` 完整验证 < 2s
- ✅ 默认使用 MD5 算法
- ✅ 仅显示验证失败的文件
- ✅ 表格格式输出，每个文件一行
- ✅ `--status` 显示差异概要
- ✅ 支持 JSON 输出

### 性能验收
- ✅ 快速检查：< 50ms（5 个文件）
- ✅ 完整验证：< 2s（45 个文件，60MB）
- ✅ MD5 计算：150MB/s

### 输出验收
- ✅ 验证成功时：仅显示汇总（无文件列表）
- ✅ 验证失败时：表格显示失败文件 + 汇总
- ✅ `--status`：简洁的差异概要
- ✅ `--json`：机器可读的 JSON 格式

---

## 注意事项

1. **默认算法改为 MD5**
   - 性能优先（150MB/s vs SHA256 的 50MB/s）
   - 适合完整性检查（非安全验证）

2. **仅显示失败文件**
   - 减少输出冗余
   - 重点关注问题

3. **表格格式**
   - 使用 Unicode box-drawing characters
   - 对齐列宽
   - 每个文件一行

4. **--status 参数**
   - 快速查看差异
   - 不执行哈希计算（仅存在性和版本）

5. **向后兼容**
   - 保留 `--hash-algorithm` 参数（支持 sha256/sha1）
   - 保留 `--skip-hash` 参数
   - 保留 `--json` 参数

---

**任务清单结束**
