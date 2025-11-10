# RustDesk 配置系统完整分析

## 目录

1. [配置系统概览](#配置系统概览)
2. [配置类型详解](#配置类型详解)
3. [配置文件位置](#配置文件位置)
4. [配置设置方式](#配置设置方式)
5. [配置优先级](#配置优先级)
6. [常用配置示例](#常用配置示例)
7. [内部实现机制](#内部实现机制)

---

## 配置系统概览

RustDesk 采用多层配置系统，支持不同场景的配置需求：

```
┌─────────────────────────────────────────────────────────┐
│                   配置系统架构                            │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │ BUILTIN      │  │ DEFAULT      │  │ OVERWRITE    │ │
│  │ SETTINGS     │  │ SETTINGS     │  │ SETTINGS     │ │
│  │ (内置/固化)   │  │ (默认值)      │  │ (强制覆盖)    │ │
│  │ 只读/内存     │  │ 只读/内存     │  │ 只读/内存     │ │
│  └──────────────┘  └──────────────┘  └──────────────┘ │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │ CONFIG       │  │ CONFIG2      │  │ LocalConfig  │ │
│  │ 基础配置      │  │ 高级配置      │  │ 本地配置      │ │
│  │ 读写/文件     │  │ 读写/文件     │  │ 读写/文件     │ │
│  └──────────────┘  └──────────────┘  └──────────────┘ │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 配置类型对比

| 配置类型 | 存储位置 | 可修改性 | 持久化 | 主要用途 |
|---------|---------|---------|-------|---------|
| **BUILTIN_SETTINGS** | 内存 | ❌ 只读 | ❌ | OEM 固化配置 |
| **DEFAULT_SETTINGS** | 内存 | ❌ 只读 | ❌ | 默认值配置 |
| **OVERWRITE_SETTINGS** | 内存 | ❌ 只读 | ❌ | 强制覆盖配置 |
| **CONFIG** | 文件 | ✅ 可修改 | ✅ | 基础配置（ID、密钥等）|
| **CONFIG2** | 文件 | ✅ 可修改 | ✅ | 高级配置（选项等）|
| **LocalConfig** | 文件 | ✅ 可修改 | ✅ | 本地UI配置 |
| **DisplaySettings** | 内存 | ❌ 只读 | ❌ | 显示设置 |

---

## 配置类型详解

### 1. BUILTIN_SETTINGS (内置配置)

**定义位置**: `libs/hbb_common/src/config.rs:72`
```rust
pub static ref BUILTIN_SETTINGS: RwLock<HashMap<String, String>> = Default::default();
```

**特点**:
- ✅ **只读配置**：运行时无法修改
- ✅ **内存存储**：不保存到文件
- ✅ **启动加载**：从配置文件/加密字符串加载
- ✅ **OEM 定制**：主要用于自定义客户端

**支持的选项** (`libs/hbb_common/src/config.rs:2732-2753`):
```rust
pub const KEYS_BUILDIN_SETTINGS: &[&str] = &[
    OPTION_DISPLAY_NAME,                    // 显示名称
    OPTION_DISABLE_UDP,                     // 禁用 UDP
    OPTION_PRESET_DEVICE_GROUP_NAME,        // 预设设备组
    OPTION_PRESET_USERNAME,                 // 预设用户名
    OPTION_HIDE_SECURITY_SETTINGS,          // 隐藏安全设置
    OPTION_HIDE_NETWORK_SETTINGS,           // 隐藏网络设置
    OPTION_HIDE_SERVER_SETTINGS,            // 隐藏服务器设置
    OPTION_HIDE_TRAY,                       // 隐藏托盘图标
    OPTION_HIDE_USERNAME_ON_CARD,           // 隐藏卡片用户名
    // ... 更多选项
];
```

**设置方式**:
1. **自定义配置文件** (`custom.txt`)
2. **加密配置字符串** (`--config` 参数)

**加载流程**:
```
程序启动
  ↓
src/common.rs:1553-1561 try_reload_recent_peers()
  ↓
read_custom_client(config_string)
  ↓
decode64() → verify() → parse_json()
  ↓
BUILTIN_SETTINGS.write().insert(key, value)
```

**配置示例**:
```json
{
  "app-name": "MyCompanyDesk",
  "default-settings": {
    "hide-tray": "Y",
    "display-name": "My Company Remote Desktop",
    "hide-security-settings": "Y"
  }
}
```

### 2. CONFIG (基础配置)

**定义位置**: `libs/hbb_common/src/config.rs:102-174`
```rust
#[derive(Debug, Default, Serialize, Deserialize, Clone, PartialEq)]
pub struct Config {
    pub id: String,                    // 设备 ID
    enc_id: String,                    // 加密的 ID
    pub password: String,              // 永久密码
    pub salt: String,                  // 密码盐值
    pub key_pair: (Vec<u8>, Vec<u8>), // 公私钥对
    pub key_confirmed: bool,           // 密钥已确认
    pub keys_confirmed: HashMap<String, bool>, // 确认的密钥列表
}
```

**文件路径**:
- Windows: `C:\Users\{用户}\AppData\Roaming\RustDesk\config\RustDesk.toml`
- Linux: `~/.config/RustDesk/RustDesk.toml`
- macOS: `~/Library/Application Support/RustDesk/RustDesk.toml`

**设置方式**:
- `--set-id <ID>`: 设置设备 ID
- `--password <PWD>`: 设置永久密码
- API 调用: `Config::set_password()`、`Config::set_salt()`

**示例内容**:
```toml
id = "123456789"
enc_id = "encrypted_id_string"
password = "encrypted_password"
salt = "random_salt_value"
key_pair = [[...], [...]]
key_confirmed = true
```

### 3. CONFIG2 (高级配置)

**定义位置**: `libs/hbb_common/src/config.rs:203-221`
```rust
pub struct Config2 {
    rendezvous_server: String,         // 中继服务器
    nat_type: i32,                     // NAT 类型
    serial: i32,                       // 序列号
    unlock_pin: String,                // 解锁 PIN
    trusted_devices: String,           // 信任设备列表
    socks: Option<Socks5Server>,       // Socks5 代理

    // ✅ 所有通过 --option 设置的选项都存储在这里
    pub options: HashMap<String, String>,
}
```

**文件路径**:
- Windows: `C:\Users\{用户}\AppData\Roaming\RustDesk\config\RustDesk2.toml`
- Linux: `~/.config/RustDesk/RustDesk2.toml`
- macOS: `~/Library/Application Support/RustDesk/RustDesk2.toml`

**设置方式**:
- `--option <key> <value>`: 设置选项
- `--config <encrypted_string>`: 从加密字符串导入
- `--import-config <file>`: 从文件导入
- API 调用: `Config::set_option()`、`Config::set_options()`

**示例内容**:
```toml
rendezvous_server = ""
nat_type = 0
serial = 0
unlock_pin = ""
trusted_devices = ""

[options]
custom-rendezvous-server = "rd-server.example.com"
api-server = "https://rd-server.example.com"
relay-server = "rd-server.example.com"
key = "public_key_string"
approve-mode = "password"
verification-method = "use-permanent-password"
allow-hide-cm = "Y"
direct-server = "Y"
```

**支持的选项** (`libs/hbb_common/src/config.rs:2618-2729`):
```rust
pub const KEYS_SETTINGS: &[&str] = &[
    // 服务器配置
    "custom-rendezvous-server",        // 自定义中继服务器
    "api-server",                      // API 服务器
    "relay-server",                    // 中继服务器
    "key",                            // 服务器公钥

    // 安全配置
    "approve-mode",                   // 批准模式 (click/password)
    "verification-method",            // 验证方法
    "allow-hide-cm",                  // 允许隐藏连接管理器
    "allow-logon-screen-password",    // 允许登录屏幕密码

    // 网络配置
    "direct-server",                  // 启用直连模式
    "disable-udp",                    // 禁用 UDP

    // 其他配置
    // ... 共 100+ 个选项
];
```

### 4. LocalConfig (本地配置)

**定义位置**: `libs/hbb_common/src/config.rs:1774-1846`
```rust
#[derive(Debug, Default, Serialize, Deserialize, Clone)]
pub struct LocalConfig {
    #[serde(default)]
    remote_id: String,                 // 远程 ID
    #[serde(default)]
    size: Size,                       // 窗口大小
    #[serde(default)]
    fav: Vec<String>,                 // 收藏列表
    #[serde(default)]
    options: HashMap<String, String>, // 本地选项
    // ... 更多字段
}
```

**文件路径**:
- Windows: `C:\Users\{用户}\AppData\Roaming\RustDesk\config\RustDesk_local.toml`
- Linux: `~/.config/RustDesk/RustDesk_local.toml`
- macOS: `~/Library/Application Support/RustDesk/RustDesk_local.toml`

**用途**:
- UI 状态保存
- 用户偏好设置
- 最近连接记录
- 窗口位置和大小

---

## 配置文件位置

### Windows

```
C:\Users\{用户名}\AppData\Roaming\RustDesk\config\
├── RustDesk.toml           # CONFIG - 基础配置
├── RustDesk2.toml          # CONFIG2 - 高级配置
├── RustDesk_local.toml     # LocalConfig - 本地配置
└── peers\
    └── {peer_id}.toml      # 远程设备配置
```

### Linux

```
~/.config/RustDesk/
├── RustDesk.toml           # CONFIG - 基础配置
├── RustDesk2.toml          # CONFIG2 - 高级配置
├── RustDesk_local.toml     # LocalConfig - 本地配置
└── peers/
    └── {peer_id}.toml      # 远程设备配置
```

### macOS

```
~/Library/Application Support/RustDesk/
├── RustDesk.toml           # CONFIG - 基础配置
├── RustDesk2.toml          # CONFIG2 - 高级配置
├── RustDesk_local.toml     # LocalConfig - 本地配置
└── peers/
    └── {peer_id}.toml      # 远程设备配置
```

### 自定义客户端配置

```
{可执行文件目录}/
└── custom.txt              # 自定义客户端配置（加密字符串）
```

---

## 配置设置方式

### 1. 命令行参数 (CLI)

#### 基础配置
```bash
# 设置设备 ID
sudo rustdesk --set-id 123456789

# 设置永久密码
sudo rustdesk --password MySecurePassword

# 设置解锁 PIN
sudo rustdesk --set-unlock-pin 1234
```

#### 高级选项 (存储到 CONFIG2)
```bash
# 查看选项
rustdesk --option custom-rendezvous-server

# 设置选项
sudo rustdesk --option custom-rendezvous-server rd-server.example.com
sudo rustdesk --option api-server https://rd-server.example.com
sudo rustdesk --option approve-mode password

# 列出所有选项
rustdesk --list-options
```

#### 配置导入
```bash
# 从加密字符串导入（存储到 CONFIG2）
sudo rustdesk --config "encrypted_config_string"

# 从文件导入（存储到 CONFIG2）
sudo rustdesk --import-config /path/to/config.toml
```

### 2. 自定义配置文件 (OEM)

**文件**: `{exe_dir}/custom.txt`

**格式**: Base64 编码 + 签名验证的 JSON

**解析流程**:
```
custom.txt
  ↓
Base64 解码
  ↓
签名验证 (使用硬编码的公钥)
  ↓
JSON 解析
  ↓
BUILTIN_SETTINGS (内存)
DEFAULT_SETTINGS (内存)
OVERWRITE_SETTINGS (内存)
```

**配置示例**:
```json
{
  "app-name": "MyCustomDesk",
  "default-settings": {
    "custom-rendezvous-server": "relay.mycompany.com",
    "api-server": "https://api.mycompany.com",
    "hide-tray": "Y",
    "display-name": "MyCompany Remote Desktop"
  },
  "override-settings": {
    "hide-security-settings": "Y",
    "hide-server-settings": "Y"
  }
}
```

**特点**:
- ✅ 需要签名验证（防止篡改）
- ✅ 启动时加载到内存
- ✅ 不可运行时修改
- ✅ 适合 OEM 定制

### 3. API 调用

```rust
// 设置 CONFIG2 选项
Config::set_option("approve-mode".to_string(), "password".to_string());

// 批量设置选项
let mut options = HashMap::new();
options.insert("approve-mode".to_string(), "password".to_string());
options.insert("verification-method".to_string(), "use-permanent-password".to_string());
Config::set_options(options);

// 设置密码
Config::set_password("MyPassword");

// 设置 LocalConfig
LocalConfig::set_option("key".to_string(), "value".to_string());
```

---

## 配置优先级

RustDesk 使用**分层配置系统**，不同配置源有不同的优先级：

### 读取优先级（从高到低）

```
1. OVERWRITE_SETTINGS    (最高优先级 - 强制覆盖)
   ↓ 如果没有，则检查
2. CONFIG2.options       (用户配置 - 运行时设置)
   ↓ 如果没有，则检查
3. DEFAULT_SETTINGS      (默认配置)
   ↓ 如果没有，则返回
4. "" (空字符串)
```

**实现代码** (`libs/hbb_common/src/config.rs:1011-1019`):
```rust
pub fn get_option(k: &str) -> String {
    get_or(
        &OVERWRITE_SETTINGS,      // 1. 首先检查强制覆盖
        &CONFIG2.read().unwrap().options,  // 2. 然后检查用户配置
        &DEFAULT_SETTINGS,        // 3. 最后使用默认值
        k,
    )
    .unwrap_or_default()          // 4. 都没有返回空字符串
}
```

### 特殊配置: BUILTIN_SETTINGS

`BUILTIN_SETTINGS` **不参与普通选项的优先级系统**，它是独立的：

```rust
// 普通选项读取
let value = Config::get_option("approve-mode");
// → 检查 OVERWRITE → CONFIG2 → DEFAULT

// 内置选项读取
let value = get_builtin_option("hide-tray");
// → 只检查 BUILTIN_SETTINGS
```

### 服务器配置优先级

服务器配置有特殊的优先级顺序 (`src/cli_help.rs:214-218`):

```
1. EXE_RENDEZVOUS_SERVER        (编译到二进制)
   ↓
2. custom-rendezvous-server     (CONFIG2.options - CLI 设置)
   ↓
3. PROD_RENDEZVOUS_SERVER       (运行时设置)
   ↓
4. CONFIG2.rendezvous_server    (配置文件)
   ↓
5. RENDEZVOUS_SERVERS           (硬编码默认值)
```

### 配置覆盖示例

假设有以下配置：

```rust
// DEFAULT_SETTINGS
approve-mode = "click"

// CONFIG2.options (用户通过 --option 设置)
approve-mode = "password"

// OVERWRITE_SETTINGS (自定义客户端强制)
approve-mode = "click"
```

**读取结果**:
```rust
Config::get_option("approve-mode")  // → "click" (OVERWRITE_SETTINGS 优先)
```

---

## 常用配置示例

### 1. 配置无人值守模式

```bash
# 设置永久密码
sudo rustdesk --password MySecurePassword123

# 配置无人值守选项
sudo rustdesk --option approve-mode password
sudo rustdesk --option verification-method use-permanent-password
sudo rustdesk --option allow-hide-cm Y
sudo rustdesk --option allow-logon-screen-password Y

# 验证配置
rustdesk --list-options | grep -E "approve-mode|verification-method|allow-hide-cm"
```

**配置效果**:
- ✅ 启用密码批准模式
- ✅ 使用永久密码验证
- ✅ 允许隐藏连接管理器
- ✅ 允许登录屏幕密码

### 2. 配置自定义服务器

```bash
# 配置服务器地址
sudo rustdesk --option custom-rendezvous-server relay.mycompany.com
sudo rustdesk --option api-server https://api.mycompany.com
sudo rustdesk --option relay-server relay.mycompany.com

# 配置服务器公钥（可选）
sudo rustdesk --option key "public_key_string"

# 验证配置
rustdesk --option custom-rendezvous-server
```

### 3. 启用 IP 直连模式

```bash
# 启用直连
sudo rustdesk --option direct-server Y

# 完整无人值守 + 直连配置
sudo rustdesk --password MyPassword
sudo rustdesk --option approve-mode password
sudo rustdesk --option verification-method use-permanent-password
sudo rustdesk --option allow-hide-cm Y
sudo rustdesk --option direct-server Y
```

### 4. 配置设备分配（企业部署）

```bash
# 分配到用户账号和设备组
sudo rustdesk --assign \
  --token "bearer_token_from_api" \
  --user_name admin@company.com \
  --device_group_name "Production Servers" \
  --device_name "Server-01" \
  --address_book_name "IT Department"
```

### 5. 自定义客户端配置（OEM）

**创建配置 JSON**:
```json
{
  "app-name": "MyCompanyDesk",
  "default-settings": {
    "custom-rendezvous-server": "relay.mycompany.com",
    "api-server": "https://api.mycompany.com",
    "hide-tray": "Y",
    "display-name": "MyCompany Remote Desktop",
    "hide-security-settings": "Y",
    "hide-server-settings": "Y"
  },
  "override-settings": {
    "approve-mode": "password"
  }
}
```

**生成加密字符串**:
```bash
# 使用 RustDesk 工具生成
# 1. JSON → 签名 → Base64
# 2. 将结果写入 custom.txt
```

---

## 内部实现机制

### 1. 配置加载流程

```
程序启动
  ↓
┌─────────────────────────────────────┐
│  1. 加载基础配置 (CONFIG)            │
│     libs/hbb_common/src/config.rs:552│
│     Config::load()                   │
│     ↓                                │
│     从 RustDesk.toml 加载             │
│     解密密码、ID 等敏感信息            │
└─────────────────────────────────────┘
  ↓
┌─────────────────────────────────────┐
│  2. 加载高级配置 (CONFIG2)           │
│     libs/hbb_common/src/config.rs:447│
│     Config2::load()                  │
│     ↓                                │
│     从 RustDesk2.toml 加载            │
│     加载 options 哈希表               │
└─────────────────────────────────────┘
  ↓
┌─────────────────────────────────────┐
│  3. 加载自定义配置 (BUILTIN)         │
│     src/common.rs:1553               │
│     try_reload_recent_peers()        │
│     ↓                                │
│     读取 custom.txt                   │
│     Base64 解码 → 签名验证 → 解析     │
│     ↓                                │
│     写入 BUILTIN_SETTINGS 内存        │
│     写入 DEFAULT_SETTINGS 内存        │
│     写入 OVERWRITE_SETTINGS 内存      │
└─────────────────────────────────────┘
  ↓
┌─────────────────────────────────────┐
│  4. 加载本地配置 (LocalConfig)       │
│     LocalConfig::load()              │
│     ↓                                │
│     从 RustDesk_local.toml 加载       │
└─────────────────────────────────────┘
  ↓
配置系统就绪
```

### 2. 配置保存流程

#### CONFIG2 保存流程 (--option)

```
CLI: rustdesk --option key value
  ↓
src/core_main.rs:551
crate::ipc::set_option(&args[1], &args[2])
  ↓
src/ipc.rs:1144-1152
set_option(key, value)
  ↓
获取当前所有选项
修改指定 key
  ↓
src/ipc.rs:1155-1164
set_options(HashMap)
  ↓
通过 IPC 发送到服务进程
  ↓
libs/hbb_common/src/config.rs:1001-1009
Config::set_options(value)
  ↓
CONFIG2.write().unwrap().options = value
config.store()
  ↓
libs/hbb_common/src/config.rs:471-481
Config2::store()
  ↓
加密敏感信息 (socks密码、unlock_pin)
  ↓
libs/hbb_common/src/config.rs:545-550
Config::store_(&config, "2")
  ↓
libs/hbb_common/src/config.rs:517-531
store_path(file, config)
  ↓
序列化为 TOML
写入 RustDesk2.toml
  ↓
持久化完成
```

### 3. 配置读取流程

```
应用代码调用
  ↓
Config::get_option("key")
  ↓
libs/hbb_common/src/config.rs:1011-1019
  ↓
┌─────────────────────────────────────┐
│  get_or() 多层查找                   │
├─────────────────────────────────────┤
│  1. OVERWRITE_SETTINGS.get("key")   │
│     ↓ 没有则继续                      │
│  2. CONFIG2.options.get("key")      │
│     ↓ 没有则继续                      │
│  3. DEFAULT_SETTINGS.get("key")     │
│     ↓ 没有则返回                      │
│  4. Some("") 或 None                │
└─────────────────────────────────────┘
  ↓
返回配置值
```

### 4. 内置配置加载流程

```
程序启动
  ↓
src/common.rs:1553-1561
try_reload_recent_peers()
  ↓
检查 custom.txt 是否存在
  ↓
存在: 读取文件内容
  ↓
src/common.rs:1640-1700
read_custom_client(config_string)
  ↓
┌─────────────────────────────────────┐
│  解密和验证流程                       │
├─────────────────────────────────────┤
│  1. Base64 解码                      │
│     decode64(config)                │
│  2. 签名验证                         │
│     sign::verify(&data, &public_key)│
│  3. JSON 解析                        │
│     serde_json::from_slice()        │
└─────────────────────────────────────┘
  ↓
解析成功: HashMap<String, Value>
  ↓
src/common.rs:1564-1620
read_custom_client_advanced_settings()
  ↓
┌─────────────────────────────────────┐
│  分类写入不同的配置存储                │
├─────────────────────────────────────┤
│  if key in KEYS_DISPLAY_SETTINGS:   │
│    → DISPLAY_SETTINGS.insert()      │
│  else if key in KEYS_LOCAL_SETTINGS:│
│    → LOCAL_SETTINGS.insert()        │
│  else if key in KEYS_SETTINGS:      │
│    → SERVER_SETTINGS.insert()       │
│  else if key in KEYS_BUILDIN_SETTINGS:│
│    → BUILTIN_SETTINGS.insert() ✅   │
│  else:                              │
│    → 写入所有类型 (通配)              │
└─────────────────────────────────────┘
  ↓
内置配置加载完成 (仅内存)
```

### 5. 关键数据结构

#### CONFIG2 结构
```rust
// libs/hbb_common/src/config.rs:203-221
pub struct Config2 {
    #[serde(default)]
    rendezvous_server: String,        // 中继服务器

    #[serde(default)]
    nat_type: i32,                    // NAT 类型

    #[serde(default)]
    serial: i32,                      // 序列号

    #[serde(default)]
    unlock_pin: String,               // 解锁 PIN (加密存储)

    #[serde(default)]
    trusted_devices: String,          // 信任设备列表

    #[serde(default)]
    socks: Option<Socks5Server>,      // Socks5 代理

    // ✅ 核心: 所有 --option 设置的选项
    #[serde(default)]
    pub options: HashMap<String, String>,
}
```

#### CONFIG 结构
```rust
// libs/hbb_common/src/config.rs:102-174
pub struct Config {
    #[serde(default)]
    pub id: String,                   // 设备 ID

    #[serde(default)]
    enc_id: String,                   // 加密的 ID

    #[serde(default)]
    pub password: String,             // 永久密码 (加密存储)

    #[serde(default)]
    pub salt: String,                 // 密码盐值

    #[serde(default)]
    pub key_pair: (Vec<u8>, Vec<u8>), // 公私钥对

    #[serde(default)]
    pub key_confirmed: bool,          // 密钥已确认

    #[serde(default)]
    pub keys_confirmed: HashMap<String, bool>, // 多设备密钥确认
}
```

### 6. 配置文件格式

#### RustDesk2.toml 示例
```toml
rendezvous_server = ""
nat_type = 2
serial = 0
unlock_pin = ""
trusted_devices = ""

[options]
custom-rendezvous-server = "relay.example.com"
api-server = "https://api.example.com"
relay-server = "relay.example.com"
key = "Ht4BXXXXXXXXXXXXXXXXXXXXXXs="
approve-mode = "password"
verification-method = "use-permanent-password"
allow-hide-cm = "Y"
allow-logon-screen-password = "Y"
direct-server = "Y"
```

#### RustDesk.toml 示例
```toml
id = "123456789"
enc_id = ""
password = "encrypted_password_string"
salt = "random_salt_bytes"
key_pair = [[...public_key_bytes...], [...private_key_bytes...]]
key_confirmed = true

[keys_confirmed]
"987654321" = true
"111222333" = true
```

---

## 附录

### A. 完整选项列表

详见 `libs/hbb_common/src/config.rs:2520-2753`

### B. 配置工具

- `rustdesk --list-options`: 列出所有当前配置
- `rustdesk --option <key>`: 查看指定配置
- `rustdesk --option <key> <value>`: 设置配置
- `rustdesk --status`: 查看服务状态和配置

### C. 常见问题

**Q: 如何重置所有配置？**
```bash
# 删除配置文件
rm -rf ~/.config/RustDesk/

# 或在 Windows
# del /s /q C:\Users\{用户}\AppData\Roaming\RustDesk\config\
```

**Q: 配置不生效怎么办？**
1. 检查是否有 `OVERWRITE_SETTINGS` 覆盖
2. 检查权限（某些配置需要 root/admin）
3. 重启服务: `sudo rustdesk --stop-service && sudo rustdesk --start-service`
4. 检查配置优先级

**Q: 如何备份配置？**
```bash
# 备份整个配置目录
cp -r ~/.config/RustDesk/ ~/rustdesk_config_backup/

# 恢复
cp -r ~/rustdesk_config_backup/ ~/.config/RustDesk/
```

---

**文档版本**: 1.0
**最后更新**: 2025-01-XX
**适用版本**: RustDesk 1.4.3+
