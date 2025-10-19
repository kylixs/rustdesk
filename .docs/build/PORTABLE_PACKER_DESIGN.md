# RustDesk Portable Packer 技术方案

## 概述

RustDesk Portable Packer 是一个将 RustDesk 应用打包成单文件自解压可执行程序的工具，支持 GUI 和 CLI 两种运行模式。

## 目录

- [1. 架构设计](#1-架构设计)
- [2. 打包方案](#2-打包方案)
- [3. 启动流程](#3-启动流程)
- [4. CLI 输出方案](#4-cli-输出方案)
- [5. 关键技术](#5-关键技术)
- [6. 使用指南](#6-使用指南)

---

## 1. 架构设计

### 1.1 整体架构

```
┌─────────────────────────────────────────────────────┐
│  rustdesk-portable-packer.exe (单文件)              │
│  ┌────────────────────────────────────────────────┐ │
│  │  Portable Packer 程序                          │ │
│  │  - GUI 子系统 (windows_subsystem = "windows")  │ │
│  │  - 解压逻辑                                     │ │
│  │  - 启动逻辑                                     │ │
│  │  - CLI 支持 (win_console)                      │ │
│  └────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────┐ │
│  │  data.bin (嵌入式数据)                         │ │
│  │  - RustDesk 所有文件的压缩包                   │ │
│  │  - Brotli 压缩                                  │ │
│  │  - MD5 校验和                                   │ │
│  └────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────┐ │
│  │  app_metadata.toml (元数据)                    │ │
│  │  - 时间戳                                       │ │
│  └────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

### 1.2 组件关系

```
┌────────────────┐
│   用户启动     │
└───────┬────────┘
        ↓
┌───────────────────────────────────┐
│  Portable Packer 主程序           │
│  ├─ BinaryReader (读取 data.bin) │
│  ├─ Setup (解压/验证)             │
│  └─ Execute (启动 RustDesk)       │
└───────┬───────────────────────────┘
        ↓
┌───────────────────────────────────┐
│  模式判断                          │
│  ├─ CLI 模式 (--参数)             │
│  └─ GUI 模式 (无参数/特殊名称)   │
└───────┬───────────────────────────┘
        ↓
┌────────────────┬──────────────────┐
│   CLI 模式     │    GUI 模式      │
│                │                  │
│ win_console    │  CREATE_NO_WIN   │
│ ::init()       │  DOW            │
│                │                  │
│ Stdio::        │  Stdio::null()   │
│ inherit()      │  或 inherit()    │
│                │                  │
│ .status()      │  .spawn()        │
│ (等待完成)     │  (立即返回)      │
└────────────────┴──────────────────┘
```

---

## 2. 打包方案

### 2.1 打包流程

```
┌─────────────────────────────────────┐
│  python generate.py                 │
│  -f rustdesk/                       │
│  -e rustdesk/rustdesk.exe           │
└─────────┬───────────────────────────┘
          ↓
┌─────────────────────────────────────┐
│  遍历所有文件                        │
│  for file in rustdesk/:             │
│    1. 读取文件内容                  │
│    2. Brotli 压缩 (level=11)        │
│    3. 计算 MD5 校验和               │
│    4. 记录到 md5_table              │
└─────────┬───────────────────────────┘
          ↓
┌─────────────────────────────────────┐
│  生成 data.bin                       │
│  format:                             │
│  "rustdesk"              # 魔术头    │
│  [path_len][path]        # 文件路径  │
│  [data_len][compressed]  # 压缩数据  │
│  [md5_hash]              # MD5       │
│  ...                     # 重复      │
│  "rustdesk"              # 魔术尾    │
│  [exe_path]              # 启动文件  │
└─────────┬───────────────────────────┘
          ↓
┌─────────────────────────────────────┐
│  生成 app_metadata.toml              │
│  timestamp = 1700000000000           │
└─────────┬───────────────────────────┘
          ↓
┌─────────────────────────────────────┐
│  cargo build --release               │
│  - 编译 Rust 打包器                 │
│  - 包含 data.bin (include_bytes!)   │
│  - 包含 app_metadata.toml            │
└─────────┬───────────────────────────┘
          ↓
┌─────────────────────────────────────┐
│  rustdesk-portable-packer.exe        │
│  (单文件可执行程序)                 │
└─────────────────────────────────────┘
```

### 2.2 data.bin 格式

```rust
// 格式说明
struct DataBin {
    magic_header: [u8; 8],      // "rustdesk"
    files: Vec<FileEntry>,
    magic_footer: [u8; 8],      // "rustdesk"
    exe_path: String,           // "./rustdesk.exe"
}

struct FileEntry {
    path_len: u32,              // 4 bytes, big-endian
    path: Vec<u8>,              // UTF-8 encoded
    data_len: u32,              // 4 bytes, big-endian
    compressed_data: Vec<u8>,   // Brotli compressed
    md5_hash: [u8; 32],         // 32 bytes, hex encoded
}
```

### 2.3 压缩参数

```python
# generate.py
compression_level = 11  # Brotli 最高压缩率
# 压缩率约 30-40%
# 示例: 100MB → 60-70MB
```

---

## 3. 启动流程

### 3.1 完整启动流程

```
用户双击 rustdesk-portable-packer.exe
    ↓
┌─────────────────────────────────────┐
│  1. main() 入口                      │
│  - 解析命令行参数                    │
│  - 检测运行模式                      │
└─────────┬───────────────────────────┘
          ↓
┌─────────────────────────────────────┐
│  2. 模式判断                         │
│  if is_cli_mode(&args):             │
│    → CLI 模式                       │
│  else:                               │
│    → GUI 模式                       │
└─────────┬───────────────────────────┘
          ↓
┌─────────────────────────────────────┐
│  3. BinaryReader::default()          │
│  - 读取嵌入的 data.bin               │
│  - 读取 app_metadata.toml            │
└─────────┬───────────────────────────┘
          ↓
┌─────────────────────────────────────┐
│  4. setup() 解压流程                 │
│  ├─ 检查时间戳                       │
│  ├─ 确定目标目录                     │
│  │   %LOCALAPPDATA%\rustdesk        │
│  ├─ 解压所有文件                     │
│  │   for file in data.bin:          │
│  │     - Brotli 解压                │
│  │     - 验证 MD5                   │
│  │     - 写入磁盘                   │
│  ├─ 写入 meta.toml                   │
│  └─ 返回 exe_path                    │
└─────────┬───────────────────────────┘
          ↓
┌─────────────────────────────────────┐
│  5. 执行 RustDesk                    │
│  CLI 模式: execute_cli_mode()        │
│  GUI 模式: execute()                 │
└─────────────────────────────────────┘
```

### 3.2 时间戳验证

```rust
fn is_timestamp_matches(dir: &Path, ts: &mut u64) -> bool {
    // 1. 读取嵌入的 app_metadata.toml 获取打包时间戳
    // 2. 读取本地 meta.toml 获取已解压版本的时间戳
    // 3. 比较时间戳
    //    - 匹配: 跳过解压
    //    - 不匹配: 重新解压
}
```

### 3.3 目标目录

```rust
// Windows: %LOCALAPPDATA%\rustdesk
// 示例: C:\Users\用户名\AppData\Local\rustdesk\
let dir = dirs::data_local_dir().join("rustdesk");
```

---

## 4. CLI 输出方案

### 4.1 问题背景

Portable Packer 使用 `#![windows_subsystem = "windows"]` 编译为 GUI 程序：
- ✅ 优点: 双击运行不会显示黑窗口
- ❌ 问题: CLI 模式下无法输出到控制台

### 4.2 解决方案：使用 win_console

```rust
// libs/portable/src/main.rs

/// 检测 CLI 模式
fn is_cli_mode(args: &Vec<String>) -> bool {
    args.iter().any(|arg| arg.starts_with("--"))
}

/// CLI 模式执行
fn execute_cli_mode(path: PathBuf, args: Vec<String>) {
    // 1. 初始化 win_console
    //    - AttachConsole(ATTACH_PARENT_PROCESS)
    //    - 附加到父控制台
    win_console::init();

    // 2. 设置环境变量
    let exe = std::env::current_exe().unwrap_or_default();
    let exe_name = exe.file_name().unwrap_or_default();

    // 3. 执行 rustdesk.exe
    let mut cmd = Command::new(&path);
    cmd.args(&args)
        .env(APPNAME_RUNTIME_ENV_KEY, exe_name)
        .stdin(Stdio::inherit())   // 继承标准输入
        .stdout(Stdio::inherit())  // 继承标准输出
        .stderr(Stdio::inherit()); // 继承标准错误

    // 4. 等待执行完成并传递退出码
    match cmd.status() {
        Ok(status) => {
            std::process::exit(status.code().unwrap_or(1));
        }
        Err(e) => {
            eprintln!("Failed to execute rustdesk: {}", e);
            std::process::exit(1);
        }
    }
}
```

### 4.3 工作原理

```
PowerShell 执行: rustdesk-portable-packer.exe --version
    ↓
┌────────────────────────────────────────────────┐
│  Portable Packer (GUI 程序)                    │
│  - 无控制台窗口                                 │
│  - println! 无法输出                           │
└────────┬───────────────────────────────────────┘
         ↓ 检测到 CLI 参数
┌────────────────────────────────────────────────┐
│  win_console::init()                            │
│  - AttachConsole(ATTACH_PARENT_PROCESS)        │
│  - 附加到 PowerShell 的控制台                  │
│  ✓ 现在 packer 可以输出到控制台了              │
└────────┬───────────────────────────────────────┘
         ↓ setup() 解压
┌────────────────────────────────────────────────┐
│  execute_cli_mode()                             │
│  - Stdio::inherit() 继承 packer 的 stdio       │
│  - rustdesk.exe 也会初始化 win_console          │
│  - 输出会通过继承的 stdio 到达控制台            │
└────────┬───────────────────────────────────────┘
         ↓
┌────────────────────────────────────────────────┐
│  PowerShell 控制台                              │
│  输出: 1.4.3 ✅                                 │
└────────────────────────────────────────────────┘
```

### 4.4 支持的终端

| 终端 | 直接输出 | 管道 (\|) | 重定向 (>) | 提示符推进 |
|------|---------|-----------|-----------|-----------|
| PowerShell | ✅ | ✅ | ✅ | ✅ (自动) |
| CMD | ✅ | ✅ | ✅ | ✅ (自动) |
| Git Bash | ✅ | ✅ | ✅ | N/A |

### 4.5 依赖配置

```toml
# libs/portable/Cargo.toml
[dependencies]
win_console = { path = "../win_console" }
```

---

## 5. 关键技术

### 5.1 Brotli 压缩

```python
# generate.py
import brotli

content = f.read()
compressed = brotli.compress(content, quality=11)
# quality=11: 最高压缩率，但速度较慢
# 适用于分发场景，一次压缩多次解压
```

**性能指标**:
- 压缩率: ~30-40%
- 压缩时间: ~30秒 (100MB)
- 解压时间: ~1秒 (100MB)

### 5.2 MD5 校验

```python
# generate.py
from hashlib import md5

md5_generator = md5()
md5_generator.update(content)
md5_code = md5_generator.hexdigest()
```

**用途**:
- 验证文件完整性
- 检测文件是否被修改

### 5.3 Windows 子系统切换

```rust
// GUI 程序配置
#![windows_subsystem = "windows"]
```

**效果**:
- ✅ 双击启动无黑窗口
- ❌ 默认无法输出到控制台
- ✅ 通过 win_console::init() 附加到控制台

### 5.4 进程创建标志

```rust
// GUI 模式
cmd.creation_flags(winapi::um::winbase::CREATE_NO_WINDOW);
// 子进程不创建窗口

// CLI 模式
// 不使用 CREATE_NO_WINDOW
// 允许子进程继承控制台
```

### 5.5 Stdio 继承

```rust
// CLI 模式: 继承 stdio
cmd.stdin(Stdio::inherit())
   .stdout(Stdio::inherit())
   .stderr(Stdio::inherit());

// GUI 模式: null stdio (或 inherit for Windows 10+)
if use_null_stdio() {
    cmd.stdin(Stdio::null())
       .stdout(Stdio::null())
       .stderr(Stdio::null());
}
```

---

## 6. 使用指南

### 6.1 构建 Portable 包

```bash
# 1. 编译 RustDesk
cargo build --release --features flutter,hwcodec

# 2. 准备 rustdesk 目录
# (通常通过 build.py 自动生成)

# 3. 生成打包数据
cd libs/portable
python generate.py \
    -f ../../rustdesk/ \
    -o . \
    -e ../../rustdesk/rustdesk.exe

# 4. 编译 Portable Packer
cargo build --release

# 5. 重命名输出
mv ../../target/release/rustdesk-portable-packer.exe \
   ../../SignOutput/rustdesk-1.4.3-x86_64.exe
```

### 6.2 使用 Portable 包

**GUI 模式**:
```bash
# 双击运行
rustdesk-1.4.3-x86_64.exe

# 自动解压到 %LOCALAPPDATA%\rustdesk
# 启动 RustDesk GUI
```

**CLI 模式**:
```bash
# 查看版本
rustdesk-1.4.3-x86_64.exe --version
# 输出: 1.4.3

# 查看帮助
rustdesk-1.4.3-x86_64.exe --help

# 查看状态
rustdesk-1.4.3-x86_64.exe --status

# 管道使用
rustdesk-1.4.3-x86_64.exe --version | Out-File version.txt
```

### 6.3 特殊文件名

```bash
# 安装模式
rustdesk-1.4.3-x86_64-install.exe
# 等同于: rustdesk.exe --install

# 快速支持模式
rustdesk-1.4.3-x86_64-qs.exe
# 等同于: rustdesk.exe --quick_support
```

### 6.4 构建脚本集成

```powershell
# build.ps1
if ($EnablePortable) {
    # 1. 修改 manifest
    (Get-Content $ManifestPath) |
        Where-Object { $_ -notmatch 'dpiAware' } |
        Set-Content $ManifestPath

    # 2. 安装依赖
    cd libs\portable
    pip install -r requirements.txt

    # 3. 生成打包数据
    python generate.py -f ..\..\rustdesk\ -o . -e ..\..\rustdesk\rustdesk.exe

    # 4. 编译 packer (在项目根目录)
    cd ..\..
    # cargo build --release 会自动编译 portable packer

    # 5. 移动输出
    Move-Item .\target\release\rustdesk-portable-packer.exe `
              .\SignOutput\rustdesk-$($env:VERSION)-x86_64.exe -Force
}
```

---

## 7. 性能优化

### 7.1 解压优化

```rust
// 缓存已解压的版本
fn is_timestamp_matches(dir: &Path, ts: &mut u64) -> bool {
    // 如果时间戳匹配，跳过解压
    // 首次运行: 需要解压 (~3-5秒)
    // 后续运行: 跳过解压 (~0.1秒)
}
```

### 7.2 压缩级别选择

```python
# 分发包: quality=11 (最高压缩)
brotli.compress(content, quality=11)

# 测试用: quality=5 (平衡)
brotli.compress(content, quality=5)
```

### 7.3 并行解压

```rust
// 当前: 单线程顺序解压
// 优化: 可以使用 rayon 并行解压多个文件
// 注意: 需要平衡 CPU 和 磁盘 I/O
```

---

## 8. 故障排查

### 8.1 CLI 输出问题

**症状**: CLI 命令无输出

**检查**:
```rust
// 1. 确认 is_cli_mode 检测正确
fn is_cli_mode(args: &Vec<String>) -> bool {
    args.iter().any(|arg| arg.starts_with("--"))
}

// 2. 确认 win_console::init() 被调用
// 3. 确认使用 Stdio::inherit()
// 4. 确认使用 .status() 而非 .spawn()
```

### 8.2 解压失败

**症状**: 文件损坏或 MD5 不匹配

**检查**:
```rust
// 1. 检查 data.bin 是否正确嵌入
const DATA: &[u8] = include_bytes!("../data.bin");

// 2. 检查 Brotli 解压
let decompressed = brotli::decompress(&compressed, buffer);

// 3. 检查 MD5 验证
if computed_md5 != stored_md5 {
    eprintln!("MD5 mismatch for file: {}", path);
}
```

### 8.3 启动失败

**症状**: RustDesk 无法启动

**检查**:
```rust
// 1. 检查 exe_path 是否正确
let exe_path = dir.join(&reader.exe);

// 2. 检查文件权限
// 3. 检查依赖 DLL 是否完整解压
```

---

## 9. 未来改进

### 9.1 增量更新

```rust
// 当前: 全量解压
// 改进: 仅解压变化的文件
fn incremental_extract() {
    for file in data.bin {
        if file.md5 != local_md5 {
            extract(file);
        }
    }
}
```

### 9.2 多线程解压

```rust
use rayon::prelude::*;

files.par_iter().for_each(|file| {
    extract_file(file);
});
```

### 9.3 压缩算法优化

```rust
// 考虑使用 zstd 代替 Brotli
// - 更快的解压速度
// - 相似的压缩率
// - 更好的内存占用
```

---

## 10. 参考资料

- **Brotli 压缩**: https://github.com/google/brotli
- **win_console 库**: `libs/win_console/DESIGN.md`
- **Windows API**: https://docs.microsoft.com/en-us/windows/console/
- **Rust Process**: https://doc.rust-lang.org/std/process/

---

## 附录 A: 目录结构

```
libs/portable/
├── Cargo.toml               # 依赖配置
├── build.rs                 # 构建脚本
├── generate.py              # 打包脚本
├── requirements.txt         # Python 依赖
├── PORTABLE_PACKER_DESIGN.md  # 本文档
├── src/
│   ├── main.rs              # 主程序入口
│   ├── bin_reader.rs        # data.bin 读取器
│   └── ui.rs                # UI 组件
├── data.bin                 # 生成的打包数据
└── app_metadata.toml        # 元数据
```

---

## 附录 B: 数据流图

```
┌──────────────┐
│  源文件目录   │ rustdesk/
│  - *.dll     │
│  - *.exe     │
│  - data/     │
└──────┬───────┘
       ↓ generate.py
┌──────────────┐
│  data.bin    │
│  - 压缩      │
│  - MD5       │
└──────┬───────┘
       ↓ include_bytes!
┌──────────────┐
│  Packer.exe  │
│  (嵌入)      │
└──────┬───────┘
       ↓ 用户启动
┌──────────────┐
│  解压到      │
│  %APPDATA%   │
└──────┬───────┘
       ↓
┌──────────────┐
│  rustdesk.exe│
│  运行中      │
└──────────────┘
```

---

**文档版本**: 1.0
**最后更新**: 2025-01-19
**作者**: Claude Code
