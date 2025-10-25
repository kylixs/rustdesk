# RustDesk 设备列表功能 - 技术设计文档

**版本**: 2.0
**日期**: 2025-10-25
**状态**: 设计评审中
**文档类型**: 架构设计与规范

---

## 文档说明

本文档为纯设计规范文档,仅包含:
- ✅ 需求分析和功能定义
- ✅ 架构设计和数据模型
- ✅ 流程图和交互逻辑
- ✅ 接口规范和文件结构
- ❌ **不包含**具体代码实现

---

## 目录

- [1. 需求分析](#1-需求分析)
- [2. 架构设计](#2-架构设计)
- [3. 数据模型设计](#3-数据模型设计)
- [4. 功能模块设计](#4-功能模块设计)
- [5. 用户交互设计](#5-用户交互设计)
- [6. 技术方案](#6-技术方案)
- [7. 文件结构规划](#7-文件结构规划)
- [8. 测试策略](#8-测试策略)
- [9. 实施计划](#9-实施计划)

---

## 1. 需求分析

### 1.1 业务背景

**目标用户**: IT管理员、运维人员、需要管理多台远程设备的用户

**核心痛点**:
- 现有通讯录功能需要云端登录,不适合纯本地管理场景
- 无法快速访问常用设备列表
- 缺少命令行批量导入设备的能力

**解决方案**: 在远程桌面窗口底部添加本地设备列表面板,支持快速连接和批量管理

---

### 1.2 功能需求

#### 1.2.1 核心功能

| 功能ID | 功能描述 | 优先级 |
|--------|---------|--------|
| F1 | 在远程桌面窗口底部显示设备列表面板 | P0 |
| F2 | 支持通过 `rustdesk --devices` 独立启动设备管理窗口 | P0 |
| F3 | 支持ID和IP两种连接方式 | P0 |
| F4 | 支持命令行批量导入设备(JSON/CSV格式) | P0 |
| F5 | 密码自动加密存储 | P0 |
| F6 | 搜索/过滤功能(按名称、IP、ID、备注) | P0 |
| F7 | 面板高度可拖动调整 | P1 |
| F8 | 面板折叠/展开 | P1 |

#### 1.2.2 非功能需求

| 需求ID | 需求描述 | 指标 |
|--------|---------|------|
| NF1 | 不修改主窗口(DesktopHomePage) | 代码隔离 |
| NF2 | 设备列表由Flutter实现,本地存储 | 不使用WebView |
| NF3 | 暂不检测设备在线状态 | 简化实现 |
| NF4 | 跨平台支持(Windows/Linux/macOS) | 配置文件路径适配 |

---

### 1.3 用户场景

#### 场景1: IT管理员批量管理设备

**角色**: 企业IT管理员
**需求**: 管理100+台办公电脑,需要快速连接和批量导入

**流程**:
```
1. 使用Excel维护设备清单(导出为CSV)
2. 运行命令: rustdesk --import-devices devices.csv
3. 运行命令: rustdesk --devices
4. 在设备列表中点击[连接]按钮,快速远程支持
```

---

#### 场景2: 运维人员管理生产服务器

**角色**: 系统运维工程师
**需求**: 管理多台生产服务器,需要区分IP直连和ID连接

**流程**:
```
1. 创建devices.json,配置服务器IP和端口
2. 通过 rustdesk --devices 打开设备管理窗口
3. 使用搜索框快速定位目标服务器
4. 点击[连接],通过IP直连方式连接服务器
```

---

## 2. 架构设计

### 2.1 系统架构

```
┌─────────────────────────────────────────────────────────────┐
│                     用户层 (User Layer)                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  主窗口       │  │ 远程桌面窗口  │  │ 命令行工具    │      │
│  │ (不修改)      │  │ (新增面板)    │  │ (批量导入)    │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────┼─────────────────────────────────┐
│                     展示层 (Presentation Layer)              │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │         DeviceListPanel (Flutter Widget)             │   │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐     │   │
│  │  │ 搜索框      │  │ 设备表格    │  │ 操作按钮    │     │   │
│  │  └────────────┘  └────────────┘  └────────────┘     │   │
│  └──────────────────────────────────────────────────────┘   │
│                              │                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │           DeviceListModel (State Management)         │   │
│  │  - 设备列表状态                                        │   │
│  │  - 搜索过滤状态                                        │   │
│  │  - 加载/保存/连接逻辑                                  │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────┼─────────────────────────────────┘
                              │
┌─────────────────────────────┼─────────────────────────────────┐
│                     数据层 (Data Layer)                       │
│                                                               │
│  ┌─────────────────┐         ┌─────────────────┐            │
│  │  Rust FFI       │◄────────┤ Flutter Bridge  │            │
│  │  - 文件读写      │         │ - FFI调用封装    │            │
│  │  - 密码加密      │         │ - 数据转换       │            │
│  │  - CSV解析      │         └─────────────────┘            │
│  └─────────────────┘                                         │
│         │                                                    │
│         ▼                                                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │          本地存储 (devices.json)                     │   │
│  │  - Linux:   ~/.config/rustdesk/devices.json        │   │
│  │  - Windows: %APPDATA%/RustDesk/devices.json        │   │
│  │  - macOS:   ~/Library/Application Support/...      │   │
│  └─────────────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────────────┘
```

---

### 2.2 技术栈

| 层次 | 技术选型 | 说明 |
|------|---------|------|
| 前端UI | Flutter | 跨平台UI框架,不使用WebView |
| 状态管理 | Provider + ChangeNotifier | Flutter官方推荐方案 |
| 后端逻辑 | Rust | 文件IO、密码加密、CSV解析 |
| FFI通信 | flutter_rust_bridge | Flutter与Rust通信 |
| 数据存储 | JSON文件 | 本地文件存储,无需数据库 |
| 密码加密 | RustDesk现有机制 | 复用 `encrypt_str_or_original` |

---

### 2.3 模块划分

```
rustdesk/
├── src/                          # Rust后端
│   ├── device_list.rs            # 设备列表核心逻辑 (新增)
│   ├── flutter_ffi.rs            # FFI接口 (修改)
│   └── core_main.rs              # 命令行参数处理 (修改)
│
└── flutter/
    ├── lib/
    │   ├── models/
    │   │   └── device_list_model.dart     # 数据模型 (新增)
    │   │
    │   ├── desktop/
    │   │   ├── widgets/
    │   │   │   └── device_list_panel.dart # UI组件 (新增)
    │   │   │
    │   │   └── pages/
    │   │       ├── remote_tab_page.dart   # 远程窗口 (修改)
    │   │       └── desktop_home_page.dart # 主窗口 (不修改)
    │   │
    │   └── main.dart                      # 启动入口 (修改)
    │
    └── assets/
        └── examples/
            ├── devices.json               # 示例配置
            └── devices.csv                # 示例配置
```

---

## 3. 数据模型设计

### 3.1 设备配置文件格式

#### 3.1.1 文件路径规范

| 平台 | 配置文件路径 |
|------|-------------|
| Linux | `~/.config/rustdesk/devices.json` |
| Windows | `%APPDATA%/RustDesk/devices.json` |
| macOS | `~/Library/Application Support/RustDesk/devices.json` |

---

#### 3.1.2 JSON数据结构

```json
{
  "version": "1.0",
  "default_connection_mode": "id",
  "devices": [
    {
      "name": "开发机1",
      "id": "123456789",
      "ip": "",
      "port": 21118,
      "password": "encrypted_xxx",
      "platform": "Windows",
      "note": "办公室主机",
      "username": "admin",
      "hostname": "DEV-PC-01"
    },
    {
      "name": "服务器A",
      "id": "",
      "ip": "192.168.1.100",
      "port": 21118,
      "password": "",
      "platform": "Linux",
      "note": "生产环境"
    }
  ]
}
```

**重要说明**:
- `id` 和 `ip` 为**独立字段**,不使用 `connection_type` + `target` 模式
- 连接时优先级: `ip` > `id` (如果 `ip` 非空,使用IP连接;否则使用ID连接)
- `default_connection_mode` 仅用于UI提示,不影响实际连接逻辑

---

#### 3.1.3 CSV数据结构

```csv
name,id,ip,port,password,platform,note,username,hostname
开发机1,123456789,,21118,plain_password,Windows,办公室主机,admin,DEV-PC-01
服务器A,,192.168.1.100,21118,,Linux,生产环境,,SRV-01
测试机,987654321,,21118,,macOS,测试用,,TEST-MAC
```

**字段说明**:
- CSV第一行为表头(字段名)
- 空字段用 `,` 分隔,不使用 `null` 或 `""`
- `id` 和 `ip` 至少有一个非空

---

### 3.2 字段定义

| 字段名 | 类型 | 必填 | 默认值 | 说明 |
|--------|------|------|--------|------|
| name | String | ✅ | - | 设备显示名称(唯一标识符) |
| id | String | ❌ | "" | RustDesk ID(9位数字) |
| ip | String | ❌ | "" | IP地址或域名 |
| port | Int | ❌ | 21118 | 连接端口 |
| password | String | ❌ | "" | 加密后的密码(空则连接时提示) |
| platform | String | ❌ | "" | 平台标识: Windows/Linux/macOS |
| note | String | ❌ | "" | 备注信息 |
| username | String | ❌ | "" | 远程主机用户名 |
| hostname | String | ❌ | "" | 主机名 |

**约束规则**:
1. `name` 必须唯一
2. `id` 和 `ip` 至少一个非空
3. `id` 非空时,必须为9位数字
4. `ip` 非空时,必须为有效的IPv4/IPv6地址或域名
5. `port` 范围: 1-65535
6. `password` 格式:
   - 明文: 直接填写密码文本
   - 加密: 以 `enc:` 开头的加密字符串

---

### 3.3 连接逻辑规则

```
决策树:
┌─────────────┐
│ 开始连接设备 │
└──────┬──────┘
       │
       ▼
   ┌───────┐
   │ip非空?│
   └───┬───┘
       │
  YES  │  NO
   ┌───▼───┐   ┌───▼───┐
   │IP直连  │   │ID连接 │
   │模式    │   │模式   │
   └───┬───┘   └───┬───┘
       │           │
       ▼           ▼
  连接到IP:port  连接到ID(通过中继服务器)
```

**伪代码逻辑**:
```
function connectDevice(device):
    if device.ip is not empty:
        // IP直连模式
        target = device.ip + ":" + device.port
        connectViaIP(target, device.password)
    else if device.id is not empty:
        // ID连接模式
        connectViaID(device.id, device.password)
    else:
        error("设备必须配置ID或IP")
```

---

### 3.4 数据验证规则

#### 导入时验证

| 验证项 | 规则 | 错误处理 |
|--------|------|---------|
| name非空 | `name.length > 0` | 跳过该设备,输出警告 |
| id或ip非空 | `id.length > 0 OR ip.length > 0` | 跳过该设备,输出警告 |
| id格式 | `id.length == 9 AND id is numeric` | 跳过该设备,输出警告 |
| port范围 | `1 <= port <= 65535` | 使用默认值21118 |
| 名称唯一性 | 检查是否与现有设备重名 | 覆盖现有设备(可配置) |

---

## 4. 功能模块设计

### 4.1 命令行功能模块

#### 4.1.1 功能列表

| 命令 | 功能描述 | 参数 |
|------|---------|------|
| `rustdesk --devices` | 打开设备管理窗口 | 无 |
| `rustdesk --import-devices <file>` | 批量导入设备 | 文件路径(JSON/CSV) |
| `rustdesk --import-devices <file> --verbose` | 详细输出导入过程 | `--verbose` |
| `rustdesk --import-devices <file> --quiet` | 静默导入(仅返回退出码) | `--quiet` |

---

#### 4.1.2 导入流程设计

```
┌─────────────────┐
│ 用户执行导入命令 │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 读取并解析文件   │
│ (JSON/CSV)      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 验证设备数据     │
│ - 必填字段检查   │
│ - 格式验证       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 密码加密处理     │
│ - 检测明文密码   │
│ - 调用加密函数   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 加载现有设备列表 │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 合并设备数据     │
│ - 按name匹配     │
│ - 新增/更新      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 保存到devices.json│
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 输出导入结果     │
│ - 成功数量       │
│ - 跳过数量       │
│ - 错误信息       │
└─────────────────┘
```

---

#### 4.1.3 输出格式设计

**默认模式** (简洁):
```
✓ Imported 10 devices (3 updated, 7 new)
⚠ Skipped 2 invalid entries
```

**详细模式** (`--verbose`):
```
Importing devices from: devices.json
Format detected: JSON

Processing devices:
  ✓ [NEW] 开发机1 (123456789)
  ✓ [UPDATE] 服务器A (192.168.1.100)
  ⚠ [SKIP] Line 5: Missing required field 'name'

Summary:
  Total entries: 12
  Successfully imported: 10 (7 new, 3 updated)
  Skipped: 2
  Encrypted 8 plain-text passwords

Saved to: /home/user/.config/rustdesk/devices.json
```

**静默模式** (`--quiet`):
- 无标准输出
- 退出码: 0=成功, 1=失败

---

### 4.2 UI功能模块

#### 4.2.1 设备列表面板

**组件结构**:
```
DeviceListPanel
├── PanelHeader (固定高度40px)
│   ├── 图标 + 标题 "Device List"
│   ├── 搜索框 (实时过滤)
│   ├── 折叠按钮 (▲/▼)
│   └── 设置按钮 (预留)
│
├── DragableDivider (可拖动分隔条)
│
└── DeviceTable (可滚动表格)
    ├── 表头行 (Name, IP/ID, Platform, Note, Action)
    └── 数据行 (N行设备数据)
        └── [连接] 按钮
```

---

#### 4.2.2 设备表格列定义

| 列名 | 宽度 | 对齐 | 内容 |
|------|------|------|------|
| Name | 120px | 左对齐 | 设备名称 |
| IP/ID | 150px | 左对齐 | 显示IP或ID(优先IP) |
| Platform | 100px | 居中 | 平台图标 + 名称 |
| Note | 自适应 | 左对齐 | 备注信息(可截断) |
| Action | 100px | 居中 | [连接] 按钮 |

---

#### 4.2.3 搜索过滤逻辑

**搜索范围**:
- 设备名称 (`name`)
- IP地址 (`ip`)
- RustDesk ID (`id`)
- 备注信息 (`note`)
- 用户名 (`username`)
- 主机名 (`hostname`)

**匹配规则**:
- 不区分大小写
- 部分匹配(包含即可)
- 实时过滤(输入即生效)

**伪代码**:
```
function filterDevices(query, devices):
    if query is empty:
        return devices

    filtered = []
    query_lower = query.toLowerCase()

    for device in devices:
        if (
            device.name.toLowerCase().contains(query_lower) OR
            device.ip.toLowerCase().contains(query_lower) OR
            device.id.toLowerCase().contains(query_lower) OR
            device.note.toLowerCase().contains(query_lower) OR
            device.username.toLowerCase().contains(query_lower) OR
            device.hostname.toLowerCase().contains(query_lower)
        ):
            filtered.append(device)

    return filtered
```

---

### 4.3 数据持久化模块

#### 4.3.1 存储架构

```
┌─────────────────────────────────────────────────────┐
│               Flutter (DeviceListModel)             │
│  ┌──────────────┐         ┌──────────────┐         │
│  │  内存状态     │◄────────┤ 加载/保存接口│         │
│  │ List<Device> │         └──────┬───────┘         │
│  └──────────────┘                │                 │
└──────────────────────────────────┼──────────────────┘
                                   │ FFI调用
┌──────────────────────────────────┼──────────────────┐
│                  Rust Backend    │                  │
│  ┌────────────────────────────────▼───────────────┐ │
│  │         device_list.rs                         │ │
│  │  - load_device_list() -> JSON String          │ │
│  │  - save_device_list(json_str) -> Result       │ │
│  └────────────────────┬───────────────────────────┘ │
└────────────────────────┼──────────────────────────────┘
                         │ 文件IO
┌────────────────────────▼──────────────────────────────┐
│          本地文件系统 (devices.json)                   │
└───────────────────────────────────────────────────────┘
```

---

#### 4.3.2 FFI接口规范

| 接口名称 | 参数 | 返回值 | 说明 |
|---------|------|--------|------|
| `main_get_device_list()` | 无 | JSON字符串 | 读取设备列表 |
| `main_save_device_list(json_str)` | JSON字符串 | "OK"或错误信息 | 保存设备列表 |

**JSON格式**: 与 [3.1.2节](#312-json数据结构) 定义一致

---

## 5. 用户交互设计

### 5.1 窗口启动交互

#### 5.1.1 主窗口启动 (不修改)

```
用户操作: 双击 rustdesk.exe
         │
         ▼
系统行为: 打开 DesktopHomePage (主窗口)
         - 显示连接输入框
         - 显示通讯录
         - **不显示设备列表**
```

---

#### 5.1.2 设备管理窗口启动

```
用户操作: rustdesk --devices
         │
         ▼
系统行为: 打开 ConnectionTabPage (远程窗口)
         │
         ├─ 顶部标签栏: 无标签
         ├─ 中间区域: 显示欢迎页
         │   "Welcome to RustDesk Device Manager"
         │   "Select a device from the list below to connect"
         │   [向下箭头图标]
         │
         └─ 底部面板: 设备列表 (展开状态, 150px高度)
```

---

### 5.2 设备连接交互

```
用户操作: 点击设备行的 [连接] 按钮
         │
         ▼
系统逻辑: 判断连接方式
         │
    ┌────┴────┐
    │ IP非空? │
    └────┬────┘
         │
    YES  │  NO
    ┌────▼────┐     ┌────▼────┐
    │IP直连模式│     │ID连接模式│
    └────┬────┘     └────┬────┘
         │                │
         ▼                ▼
    连接到IP:port     连接到RustDesk ID
         │                │
         └────────┬───────┘
                  │
                  ▼
        ┌─────────────────┐
        │ 密码处理          │
        │ - 已保存: 自动填充│
        │ - 未保存: 弹窗提示│
        └─────────┬─────────┘
                  │
                  ▼
        ┌─────────────────┐
        │ 建立远程连接      │
        └─────────┬─────────┘
                  │
                  ▼
        ┌─────────────────┐
        │ 在顶部标签栏新增标签│
        │ 标题: 设备名称/ID  │
        └─────────────────┘
```

---

### 5.3 面板交互

#### 5.3.1 折叠/展开

```
状态转换:
┌──────────┐  点击 [▲收起]  ┌──────────┐
│ 展开状态 │──────────────→│ 折叠状态 │
│(150px高度)│                │(40px高度)│
└──────────┘←──────────────└──────────┘
            点击 [▼展开]

动画: 200ms 缓动过渡
```

---

#### 5.3.2 高度调整

```
交互流程:
1. 鼠标悬停在分隔条上
   → 鼠标指针变为 ↕ (上下调整)

2. 按住鼠标左键拖动
   → 面板高度实时变化

3. 释放鼠标左键
   → 保存高度设置(本地偏好)

约束:
- 最小高度: 80px
- 最大高度: 400px
- 超出范围时停止调整
```

---

### 5.4 搜索交互

```
用户输入: 在搜索框输入关键词 "192.168"
         │
         ▼
系统响应: 实时过滤设备列表
         │
         ├─ 显示所有包含 "192.168" 的设备
         ├─ 不匹配的设备隐藏
         └─ 表格动态调整(无重新渲染闪烁)

用户清空: 删除搜索框内容
         │
         ▼
系统响应: 显示所有设备
```

---

## 6. 技术方案

### 6.1 Flutter状态管理

**方案**: Provider + ChangeNotifier

**理由**:
- Flutter官方推荐方案
- 简单易用,适合中小规模状态管理
- 与现有RustDesk Flutter代码风格一致

**状态结构**:
```
DeviceListModel (ChangeNotifier)
├── _devices: List<DeviceConfig>          // 所有设备
├── _searchQuery: String                  // 搜索关键词
├── _defaultConnectionMode: String        // 默认连接模式
│
├── devices (getter)                      // 过滤后的设备列表
│   └── 根据 _searchQuery 实时过滤
│
├── load()                                // 加载设备列表
├── save()                                // 保存设备列表
├── addDevice(device)                     // 添加设备
├── removeDevice(name)                    // 删除设备
├── updateSearch(query)                   // 更新搜索
└── connectDevice(device)                 // 连接设备
```

---

### 6.2 密码加密方案

**方案**: 复用RustDesk现有加密机制

**函数**: `encrypt_str_or_original(password, version)`

**加密流程**:
```
明文密码 "mypassword"
         │
         ▼
   Rust加密函数
         │
         ▼
加密结果 "enc:d8f3a7b2c1e4..."
```

**导入时处理逻辑**:
```
function encryptPasswordIfNeeded(password):
    if password is empty:
        return ""

    if password.startsWith("enc:"):
        // 已加密,不重复加密
        return password
    else:
        // 明文密码,加密后返回
        return encrypt_str_or_original(password, "00")
```

---

### 6.3 CSV解析方案

**方案**: Rust端使用 `csv` crate

**依赖**: `csv = "1.1"`

**解析流程**:
```
CSV文件
  │
  ▼
csv::Reader (Rust)
  │
  ├─ 读取表头
  ├─ 逐行解析
  ├─ 字段映射到 DeviceConfig
  └─ 错误处理(跳过无效行)
  │
  ▼
Vec<DeviceConfig>
  │
  ▼
序列化为JSON
  │
  ▼
返回给Flutter
```

---

### 6.4 跨平台文件路径

**实现策略**: Rust端统一处理, 保存在 <config_dir>/devices.json

**Flutter端**: 无需关心路径,通过FFI调用Rust端接口

---

## 7. 文件结构规划

### 7.1 新增文件

| 文件路径 | 说明 | 预计代码量 |
|---------|------|-----------|
| `src/device_list.rs` | Rust端设备列表核心逻辑 | ~300行 |
| `flutter/lib/models/device_list_model.dart` | Flutter状态管理 | ~150行 |
| `flutter/lib/desktop/widgets/device_list_panel.dart` | UI组件 | ~350行 |

---

### 7.2 修改文件

| 文件路径 | 修改内容 | 预计修改量 |
|---------|---------|-----------|
| `src/core_main.rs` | 添加 `--devices` 和 `--import-devices` 参数处理 | +30行 |
| `src/flutter_ffi.rs` | 添加设备列表FFI接口 | +25行 |
| `src/lib.rs` | 添加 `mod device_list;` | +1行 |
| `flutter/lib/main.dart` | 添加 `--devices` 启动逻辑 | +30行 |
| `flutter/lib/desktop/pages/remote_tab_page.dart` | 底部添加设备列表面板 | +60行 |
| `Cargo.toml` | 添加 `csv` 依赖 | +1行 |

---

### 7.3 示例文件

| 文件路径 | 说明 |
|---------|------|
| `docs/examples/devices.json` | JSON格式示例配置 |
| `docs/examples/devices.csv` | CSV格式示例配置 |

---

## 8. 测试策略

### 8.1 单元测试

| 模块 | 测试项 | 测试工具 |
|------|--------|---------|
| Rust设备列表 | JSON解析/序列化 | `cargo test` |
| Rust设备列表 | CSV解析 | `cargo test` |
| Rust设备列表 | 密码加密 | `cargo test` |
| Flutter数据模型 | 搜索过滤逻辑 | `flutter test` |
| Flutter数据模型 | 设备验证 | `flutter test` |

---

### 8.2 集成测试

| 测试场景 | 验证点 | 测试环境 |
|---------|--------|---------|
| 导入JSON | 成功导入,数据正确 | Windows/Linux/macOS |
| 导入CSV | 成功导入,字段映射正确 | Windows/Linux/macOS |
| 密码加密 | 明文密码自动加密 | 所有平台 |
| 连接设备(ID) | 通过RustDesk ID连接 | 所有平台 |
| 连接设备(IP) | 通过IP直连 | 所有平台 |
| 搜索过滤 | 实时过滤,结果正确 | 所有平台 |
| 面板折叠 | 动画流畅,状态保存 | 所有平台 |
| 高度调整 | 拖动响应,约束生效 | 所有平台 |

---

### 8.3 手动测试清单

#### 8.3.1 命令行功能测试

- [ ] `rustdesk --devices` 启动设备管理窗口
- [ ] `rustdesk --import-devices test.json` 导入JSON
- [ ] `rustdesk --import-devices test.csv` 导入CSV
- [ ] `rustdesk --import-devices test.json --verbose` 详细输出
- [ ] `rustdesk --import-devices test.json --quiet` 静默模式
- [ ] 导入无效数据,验证错误处理

---

#### 8.3.2 UI功能测试

- [ ] 设备列表正常显示
- [ ] 搜索框实时过滤
- [ ] 点击[连接]按钮,成功连接
- [ ] 面板折叠/展开动画流畅
- [ ] 拖动分隔条,高度正常调整
- [ ] 重启应用,面板高度保持

---

#### 8.3.3 跨平台测试

- [ ] Windows平台: 配置文件路径正确
- [ ] Linux平台: 配置文件路径正确
- [ ] macOS平台: 配置文件路径正确
- [ ] 密码加密在所有平台一致

---

## 9. 实施计划

### 9.1 开发阶段

| 阶段 | 任务 | 产出 | 耗时 | 依赖 |
|------|------|------|------|------|
| 阶段1 | Rust后端开发 | device_list.rs, FFI接口 | 1-2天 | 无 |
| 阶段2 | Flutter数据模型 | device_list_model.dart | 0.5天 | 阶段1 |
| 阶段3 | Flutter UI组件 | device_list_panel.dart | 1-2天 | 阶段2 |
| 阶段4 | 集成调试 | 功能联调 | 0.5天 | 阶段3 |
| 阶段5 | 测试验证 | 测试报告 | 0.5天 | 阶段4 |
| 阶段6 | 文档完善 | 用户手册 | 0.5天 | 阶段5 |

**总计**: 4-6天

---

### 9.2 验收标准

| 验收项 | 标准 |
|--------|------|
| 功能完整性 | 所有P0功能正常工作 |
| 跨平台兼容 | Windows/Linux/macOS测试通过 |
| 性能 | 1000个设备,搜索响应<100ms |
| 代码质量 | 通过代码审查,无重大缺陷 |
| 文档 | 用户手册和示例文件完整 |

---

### 9.3 上线计划

**发布版本**: RustDesk v1.x.x

**发布内容**:
1. ✅ 设备列表功能
2. ✅ 命令行批量导入
3. ✅ 设备管理窗口
4. ✅ 用户文档和示例

**兼容性**: 向后兼容,不影响现有功能

---

## 10. 风险与对策

| 风险 | 影响 | 概率 | 对策 |
|------|------|------|------|
| 密码加密机制变更 | 导入的密码无法使用 | 低 | 预留加密版本参数,支持多版本 |
| Flutter与Rust FFI通信异常 | 功能无法正常工作 | 中 | 增加错误处理和日志 |
| CSV解析性能问题 | 大文件导入慢 | 低 | 增加进度提示,异步处理 |
| 跨平台路径差异 | 配置文件读写失败 | 中 | 充分测试,增加路径检测 |

---

## 11. 后续扩展

### Phase 2 功能规划 (可选)

| 功能 | 说明 | 优先级 |
|------|------|--------|
| UI界面管理设备 | 添加/编辑/删除设备 | P1 |
| 设备分组 | 按项目/环境分组 | P1 |
| 导出设备列表 | 导出为JSON/CSV | P2 |
| 在线状态检测 | 显示设备在线/离线 | P2 |
| 从通讯录导入 | 将云端通讯录设备添加到本地 | P2 |
| 右键菜单 | 文件传输、终端等快捷操作 | P2 |
| **远程设备管理(WebView)** | 通过Web界面管理设备 | P3 |

---

## 12. 附录

### 12.1 JSON完整示例

**文件**: `docs/examples/devices.json`

```json
{
  "version": "1.0",
  "default_connection_mode": "id",
  "devices": [
    {
      "name": "Office Desktop",
      "id": "123456789",
      "ip": "",
      "port": 21118,
      "password": "",
      "platform": "Windows",
      "note": "My office desktop computer",
      "username": "john",
      "hostname": "OFFICE-PC-01"
    },
    {
      "name": "Home Server",
      "id": "",
      "ip": "192.168.1.100",
      "port": 21118,
      "password": "",
      "platform": "Linux",
      "note": "Home lab server",
      "username": "admin",
      "hostname": "HOME-SRV-01"
    },
    {
      "name": "Development VM",
      "id": "",
      "ip": "192.168.56.10",
      "port": 21118,
      "password": "",
      "platform": "Linux",
      "note": "VirtualBox development VM"
    },
    {
      "name": "Test Mac",
      "id": "987654321",
      "ip": "",
      "port": 21118,
      "password": "",
      "platform": "macOS",
      "note": "Testing environment"
    }
  ]
}
```

---

### 12.2 CSV完整示例

**文件**: `docs/examples/devices.csv`

```csv
name,id,ip,port,password,platform,note,username,hostname
Office Desktop,123456789,,21118,,Windows,My office desktop computer,john,OFFICE-PC-01
Home Server,,192.168.1.100,21118,,Linux,Home lab server,admin,HOME-SRV-01
Development VM,,192.168.56.10,21118,,Linux,VirtualBox development VM,,
Test Mac,987654321,,21118,,macOS,Testing environment,,TEST-MAC
Production DB,,10.0.1.50,21119,,Linux,Production database server,postgres,PROD-DB-01
```

---

### 12.3 术语表

| 术语 | 说明 |
|------|------|
| RustDesk ID | RustDesk生成的9位数字唯一标识符 |
| IP直连 | 通过IP地址和端口直接连接,不经过中继服务器 |
| ID连接 | 通过RustDesk ID连接,由中继服务器协调 |
| FFI | Foreign Function Interface,Rust与Flutter的通信接口 |
| WebView | 嵌入式浏览器组件(本功能不使用) |
| Provider | Flutter状态管理库 |
| ChangeNotifier | Flutter响应式编程基类 |

---

### 12.4 参考文档

- [RustDesk官方文档](https://rustdesk.com/docs/)
- [Flutter Provider文档](https://pub.dev/packages/provider)
- [csv crate文档](https://docs.rs/csv/)
- [Flutter Rust Bridge](https://github.com/fzyzcjy/flutter_rust_bridge)

---

**文档结束**

---

**审阅签名**:

- [ ] 产品经理: ____________  日期: ______
- [ ] 技术负责人: ____________  日期: ______
- [ ] 开发工程师: ____________  日期: ______
