# 构建时修改 HIDE_TRAY 配置指南

## 目录
1. [方案对比](#方案对比)
2. [方案 1: 环境变量 + 编译时常量](#方案-1-环境变量--编译时常量)
3. [方案 2: build.rs 构建脚本](#方案-2-buildrs-构建脚本)
4. [方案 3: custom.txt 配置文件](#方案-3-customtxt-配置文件)
5. [方案 4: 代码硬编码](#方案-4-代码硬编码)
6. [推荐方案](#推荐方案)

---

## 方案对比

| 方案 | 实现难度 | 灵活性 | 维护成本 | 适用场景 |
|------|---------|--------|---------|---------|
| 环境变量 | ⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ | 临时构建、开发测试 |
| build.rs | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | CI/CD、自动化构建 |
| custom.txt | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | OEM 定制、商业发布 |
| 硬编码 | ⭐ | ⭐ | ⭐⭐⭐⭐⭐ | 固定配置、简单场景 |

---

## 方案 1: 环境变量 + 编译时常量

### 原理
在编译时通过环境变量设置默认值，运行时优先使用编译时的值。

### 实现步骤

#### 1. 修改 `libs/hbb_common/src/config.rs`

添加编译时常量：

```rust
// libs/hbb_common/src/config.rs

// 在文件开头添加
pub const DEFAULT_HIDE_TRAY: &str = option_env!("RUSTDESK_HIDE_TRAY").unwrap_or("");

// 在 lazy_static 块中修改 BUILTIN_SETTINGS 初始化
lazy_static::lazy_static! {
    // ... 其他配置
    pub static ref BUILTIN_SETTINGS: RwLock<HashMap<String, String>> = {
        let mut map = HashMap::new();

        // 如果编译时设置了 HIDE_TRAY，添加到 BUILTIN_SETTINGS
        if !DEFAULT_HIDE_TRAY.is_empty() {
            map.insert(keys::OPTION_HIDE_TRAY.to_string(), DEFAULT_HIDE_TRAY.to_string());
        }

        RwLock::new(map)
    };
}
```

#### 2. 构建时设置环境变量

**Linux/macOS**:
```bash
# 隐藏托盘
RUSTDESK_HIDE_TRAY=Y cargo build --release

# 显示托盘（默认）
cargo build --release
```

**Windows (PowerShell)**:
```powershell
# 隐藏托盘
$env:RUSTDESK_HIDE_TRAY="Y"; cargo build --release

# 显示托盘（默认）
cargo build --release
```

**Windows (CMD)**:
```cmd
set RUSTDESK_HIDE_TRAY=Y && cargo build --release
```

### 优点
- ✅ 实现简单，只需修改几行代码
- ✅ 灵活，可以在构建时动态设置
- ✅ 不需要外部配置文件

### 缺点
- ❌ 需要修改源代码
- ❌ 每次构建都需要设置环境变量

---

## 方案 2: build.rs 构建脚本

### 原理
使用 Rust 的 `build.rs` 构建脚本，在编译前自动生成配置代码。

### 实现步骤

#### 1. 创建 `build.rs` 脚本

在 `libs/hbb_common/` 目录下创建或修改 `build.rs`:

```rust
// libs/hbb_common/build.rs

use std::env;
use std::fs;
use std::path::Path;

fn main() {
    // 读取环境变量或配置文件
    let hide_tray = env::var("RUSTDESK_HIDE_TRAY")
        .or_else(|_| read_build_config("hide-tray"))
        .unwrap_or_default();

    // 生成编译时常量
    let out_dir = env::var("OUT_DIR").unwrap();
    let dest_path = Path::new(&out_dir).join("build_config.rs");

    let content = format!(
        r#"
// 自动生成的构建配置
pub const BUILD_HIDE_TRAY: &str = "{}";
"#,
        hide_tray
    );

    fs::write(&dest_path, content).unwrap();

    // 告诉 Cargo 在这些文件改变时重新运行
    println!("cargo:rerun-if-env-changed=RUSTDESK_HIDE_TRAY");
    println!("cargo:rerun-if-changed=build_config.toml");
}

/// 从配置文件读取构建配置
fn read_build_config(key: &str) -> Result<String, Box<dyn std::error::Error>> {
    use std::fs;

    let config_file = "build_config.toml";
    if !Path::new(config_file).exists() {
        return Err("Config file not found".into());
    }

    let content = fs::read_to_string(config_file)?;
    let config: toml::Value = toml::from_str(&content)?;

    Ok(config
        .get(key)
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string())
}
```

#### 2. 创建构建配置文件

```toml
# libs/hbb_common/build_config.toml

# 托盘配置
# 可选值: "Y" (隐藏) 或 "" (显示)
hide-tray = "Y"

# 其他构建时配置
# display-name = "MyCustomDesk"
# custom-server = "relay.example.com"
```

#### 3. 添加 build.rs 依赖

在 `libs/hbb_common/Cargo.toml` 中添加：

```toml
[build-dependencies]
toml = "0.5"
```

#### 4. 在代码中使用

修改 `libs/hbb_common/src/config.rs`:

```rust
// libs/hbb_common/src/config.rs

// 包含构建脚本生成的代码
include!(concat!(env!("OUT_DIR"), "/build_config.rs"));

lazy_static::lazy_static! {
    pub static ref BUILTIN_SETTINGS: RwLock<HashMap<String, String>> = {
        let mut map = HashMap::new();

        // 使用构建时配置
        if !BUILD_HIDE_TRAY.is_empty() {
            map.insert(keys::OPTION_HIDE_TRAY.to_string(), BUILD_HIDE_TRAY.to_string());
        }

        RwLock::new(map)
    };
}
```

#### 5. 构建方式

**方式 1: 使用配置文件**
```bash
# 编辑 libs/hbb_common/build_config.toml
# 设置 hide-tray = "Y"

# 构建
cargo build --release
```

**方式 2: 使用环境变量覆盖**
```bash
# 环境变量优先级高于配置文件
RUSTDESK_HIDE_TRAY=Y cargo build --release
```

### 优点
- ✅ 高度自动化，适合 CI/CD
- ✅ 支持配置文件和环境变量两种方式
- ✅ 灵活性高，易于扩展更多配置
- ✅ 配置文件可以版本控制

### 缺点
- ❌ 实现相对复杂
- ❌ 需要维护构建脚本

---

## 方案 3: custom.txt 配置文件

### 原理
使用 RustDesk 现有的 `custom.txt` 机制，在构建后添加配置文件。

### 实现步骤

#### 1. 创建配置 JSON

```json
{
  "app-name": "RustDesk",
  "default-settings": {
    "hide-tray": "Y"
  }
}
```

#### 2. 签名和编码

使用 RustDesk 提供的工具生成签名：

```bash
# 假设有签名工具
rustdesk-config-generator \
  --input config.json \
  --private-key path/to/private.key \
  --output custom.txt
```

**注意**: RustDesk 的配置签名使用硬编码的公钥验证：
```rust
// src/common.rs:1645
const KEY: &str = "5Qbwsde3unUcJBtrx9ZkvUmwFNoExHzpryHuPUdqlWM=";
```

你需要有对应的私钥才能生成有效的签名。

#### 3. 放置配置文件

将 `custom.txt` 放在可执行文件同目录：

```
/path/to/rustdesk/
├── rustdesk.exe
└── custom.txt
```

#### 4. 构建和打包

```bash
# 1. 正常构建
cargo build --release

# 2. 复制可执行文件
cp target/release/rustdesk /path/to/deploy/

# 3. 添加 custom.txt
cp custom.txt /path/to/deploy/

# 4. 打包
cd /path/to/deploy
zip rustdesk-custom.zip rustdesk custom.txt
```

### 优点
- ✅ 不需要修改源代码
- ✅ 不需要重新编译
- ✅ 配置可以随时更换
- ✅ 适合 OEM 定制

### 缺点
- ❌ 需要私钥签名（默认密钥不公开）
- ❌ 配置文件容易被删除
- ❌ 需要额外的签名工具

### 替代方案: 自定义签名密钥

如果要使用自己的密钥，需要修改源码：

```rust
// src/common.rs:1645
// 将硬编码的公钥替换为你的公钥
const KEY: &str = "YOUR_PUBLIC_KEY_BASE64";
```

然后重新编译。

---

## 方案 4: 代码硬编码

### 原理
直接在代码中硬编码默认值。

### 实现步骤

#### 修改 `libs/hbb_common/src/config.rs`

```rust
// libs/hbb_common/src/config.rs

lazy_static::lazy_static! {
    pub static ref BUILTIN_SETTINGS: RwLock<HashMap<String, String>> = {
        let mut map = HashMap::new();

        // 硬编码默认隐藏托盘
        map.insert(keys::OPTION_HIDE_TRAY.to_string(), "Y".to_string());

        // 可以添加更多硬编码配置
        // map.insert("display-name".to_string(), "MyCustomDesk".to_string());

        RwLock::new(map)
    };
}
```

### 构建

```bash
# 正常构建即可
cargo build --release
```

### 优点
- ✅ 实现最简单
- ✅ 不需要额外配置

### 缺点
- ❌ 完全不灵活
- ❌ 每次修改都需要重新编译
- ❌ 难以维护多个不同配置的版本

---

## 推荐方案

### 场景 1: 开发和测试
**推荐**: **方案 1 (环境变量)**

```bash
# 快速测试隐藏托盘
RUSTDESK_HIDE_TRAY=Y cargo run

# 测试显示托盘
cargo run
```

### 场景 2: CI/CD 自动化构建
**推荐**: **方案 2 (build.rs)**

**GitHub Actions 示例**:
```yaml
name: Build RustDesk

on: [push]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Build with hidden tray
        env:
          RUSTDESK_HIDE_TRAY: Y
        run: cargo build --release

      - name: Upload artifact
        uses: actions/upload-artifact@v2
        with:
          name: rustdesk-no-tray
          path: target/release/rustdesk
```

### 场景 3: OEM 定制发布
**推荐**: **方案 3 (custom.txt)** 或 **方案 2 (build.rs)**

**结合使用**:
```bash
# 1. 使用 build.rs 构建基础版本
echo 'hide-tray = "Y"' > libs/hbb_common/build_config.toml
cargo build --release

# 2. 添加 custom.txt 提供额外配置
cp custom.txt target/release/

# 3. 打包发布
./package.sh
```

### 场景 4: 内部固定配置
**推荐**: **方案 4 (硬编码)**

适合公司内部使用，配置固定不变的情况。

---

## 完整示例: 方案 2 详细实现

### 1. 项目结构

```
rustdesk/
├── libs/
│   └── hbb_common/
│       ├── build.rs              # ← 新建
│       ├── build_config.toml     # ← 新建
│       ├── Cargo.toml            # ← 修改
│       └── src/
│           └── config.rs         # ← 修改
└── Cargo.toml
```

### 2. build.rs 完整代码

```rust
// libs/hbb_common/build.rs

use std::env;
use std::fs;
use std::path::Path;

fn main() {
    println!("cargo:rerun-if-env-changed=RUSTDESK_HIDE_TRAY");
    println!("cargo:rerun-if-changed=build_config.toml");

    let hide_tray = get_hide_tray_config();

    generate_config_code(&hide_tray);
}

/// 获取 hide-tray 配置
/// 优先级: 环境变量 > 配置文件 > 默认值
fn get_hide_tray_config() -> String {
    // 1. 检查环境变量
    if let Ok(val) = env::var("RUSTDESK_HIDE_TRAY") {
        println!("cargo:warning=Using RUSTDESK_HIDE_TRAY from environment: {}", val);
        return val;
    }

    // 2. 检查配置文件
    if let Ok(val) = read_build_config("hide-tray") {
        println!("cargo:warning=Using hide-tray from build_config.toml: {}", val);
        return val;
    }

    // 3. 默认值（显示托盘）
    String::new()
}

/// 从 TOML 配置文件读取配置
fn read_build_config(key: &str) -> Result<String, Box<dyn std::error::Error>> {
    let config_file = "build_config.toml";

    if !Path::new(config_file).exists() {
        return Err("Config file not found".into());
    }

    let content = fs::read_to_string(config_file)?;

    // 简单的 TOML 解析（避免依赖 toml crate）
    for line in content.lines() {
        let line = line.trim();
        if line.starts_with('#') || line.is_empty() {
            continue;
        }

        if let Some((k, v)) = line.split_once('=') {
            let k = k.trim();
            let v = v.trim().trim_matches('"');

            if k == key {
                return Ok(v.to_string());
            }
        }
    }

    Err("Key not found".into())
}

/// 生成配置代码
fn generate_config_code(hide_tray: &str) {
    let out_dir = env::var("OUT_DIR").unwrap();
    let dest_path = Path::new(&out_dir).join("build_config.rs");

    let content = format!(
        r#"
// ============================================
// 自动生成的构建时配置
// 不要手动编辑此文件
// ============================================

/// 构建时设置的 hide-tray 值
pub const BUILD_HIDE_TRAY: &str = "{}";

/// 检查是否在构建时启用了隐藏托盘
pub const fn is_hide_tray_enabled() -> bool {{
    !BUILD_HIDE_TRAY.is_empty()
}}
"#,
        hide_tray
    );

    fs::write(&dest_path, content).expect("Failed to write build_config.rs");

    println!("cargo:warning=Generated build config: hide-tray = '{}'", hide_tray);
}
```

### 3. build_config.toml

```toml
# libs/hbb_common/build_config.toml

# ============================================
# RustDesk 构建时配置
# ============================================

# 托盘图标配置
# 可选值:
#   "Y"  - 隐藏托盘图标
#   ""   - 显示托盘图标 (默认)
hide-tray = "Y"

# 未来可以扩展更多配置:
# display-name = "MyCustomDesk"
# custom-server = "relay.example.com"
# disable-udp = "Y"
```

### 4. config.rs 修改

```rust
// libs/hbb_common/src/config.rs

// 在文件开头添加
include!(concat!(env!("OUT_DIR"), "/build_config.rs"));

// 修改 BUILTIN_SETTINGS 初始化
lazy_static::lazy_static! {
    // ... 其他 static ref

    pub static ref BUILTIN_SETTINGS: RwLock<HashMap<String, String>> = {
        let mut map = HashMap::new();

        // 使用构建时配置
        if !BUILD_HIDE_TRAY.is_empty() {
            log::info!("Build-time config: hide-tray = {}", BUILD_HIDE_TRAY);
            map.insert(keys::OPTION_HIDE_TRAY.to_string(), BUILD_HIDE_TRAY.to_string());
        }

        RwLock::new(map)
    };
}
```

### 5. Cargo.toml 修改

```toml
# libs/hbb_common/Cargo.toml

[package]
# ... 其他配置
build = "build.rs"  # 启用 build.rs

# build.rs 不需要额外依赖（使用简单解析）
# [build-dependencies]
# 不需要 toml crate
```

### 6. 使用方式

**方式 1: 使用配置文件**
```bash
# 编辑 libs/hbb_common/build_config.toml
# 设置 hide-tray = "Y"

cargo build --release
```

**方式 2: 使用环境变量（覆盖配置文件）**
```bash
RUSTDESK_HIDE_TRAY=Y cargo build --release
```

**方式 3: CI/CD**
```bash
# .gitlab-ci.yml 或 GitHub Actions
export RUSTDESK_HIDE_TRAY=Y
cargo build --release
```

### 7. 验证构建结果

```bash
# 构建后检查
./target/release/rustdesk --version

# 运行测试
./target/release/rustdesk --server

# 检查托盘是否隐藏
ps aux | grep rustdesk
```

---

## 总结

| 方案 | 最佳场景 | 命令示例 |
|------|---------|---------|
| 环境变量 | 开发测试 | `RUSTDESK_HIDE_TRAY=Y cargo build` |
| build.rs | CI/CD | 编辑 `build_config.toml` → `cargo build` |
| custom.txt | OEM 定制 | 构建 + 添加 `custom.txt` |
| 硬编码 | 固定配置 | 修改代码 → `cargo build` |

**推荐**: 大多数情况下使用 **方案 2 (build.rs)**，它提供了最好的灵活性和可维护性。
