# RustDesk 设备列表功能 - 使用指南

## 功能概述

设备列表功能允许您在本地管理和快速连接到常用的远程设备,无需云端登录。

### 主要特性

- ✅ 本地设备列表管理(无需云端登录)
- ✅ 支持ID连接和IP直连两种方式
- ✅ 批量导入设备(JSON/CSV格式)
- ✅ 密码自动加密存储
- ✅ 快速搜索和过滤
- ✅ 跨平台支持(Windows/Linux/macOS)

## 命令行使用

### 导入设备列表

#### 从JSON文件导入

```bash
# 基本导入
rustdesk --import-devices devices.json

# 详细输出模式
rustdesk --import-devices devices.json --verbose

# 静默模式(仅返回退出码)
rustdesk --import-devices devices.json --quiet
```

#### 从CSV文件导入

```bash
rustdesk --import-devices devices.csv
```

### 打开设备管理窗口

```bash
rustdesk --devices
```

## 配置文件格式

### JSON格式

**文件路径**:
- Linux: `~/.config/rustdesk/devices.json`
- Windows: `%APPDATA%/RustDesk/devices.json`
- macOS: `~/Library/Application Support/RustDesk/devices.json`

**示例**: 参见 `docs/examples/devices.json`

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
            "note": "My office desktop",
            "username": "john",
            "hostname": "OFFICE-PC-01"
        }
    ]
}
```

### CSV格式

**示例**: 参见 `docs/examples/devices.csv`

```csv
name,id,ip,port,password,platform,note,username,hostname
Office Desktop,123456789,,21118,,Windows,My office desktop,john,OFFICE-PC-01
Home Server,,192.168.1.100,21118,,Linux,Home lab server,admin,HOME-SRV-01
```

### 字段说明

| 字段名 | 类型 | 必填 | 默认值 | 说明 |
|--------|------|------|--------|------|
| name | String | ✅ | - | 设备显示名称(唯一) |
| id | String | ❌ | "" | RustDesk ID(9位数字) |
| ip | String | ❌ | "" | IP地址或域名 |
| port | Int | ❌ | 21118 | 连接端口 |
| password | String | ❌ | "" | 密码(明文或已加密) |
| platform | String | ❌ | "" | Windows/Linux/macOS |
| note | String | ❌ | "" | 备注信息 |
| username | String | ❌ | "" | 远程主机用户名 |
| hostname | String | ❌ | "" | 主机名 |

**约束规则**:
- `name` 必须唯一
- `id` 和 `ip` 至少提供一个
- `id` 必须为9位数字
- 密码可以是明文(导入时自动加密)或已加密(以版本号开头,如 `00xxx...`)

## 连接方式

### IP直连 vs ID连接

**优先级**: IP > ID

- 如果设备配置了 `ip` 字段(非空),使用IP直连: `ip:port`
- 否则使用ID连接: 通过RustDesk ID连接

**示例**:

```json
{
    "name": "Server-IP",
    "ip": "192.168.1.100",
    "port": 21118
    // 使用IP直连: 192.168.1.100:21118
}
```

```json
{
    "name": "Desktop-ID",
    "id": "123456789"
    // 使用ID连接: 123456789
}
```

## 密码安全

### 自动加密

导入时,明文密码会自动加密:

```
明文密码: "mypassword"
     ↓
加密后: "00HIbNpnmvMiNYhObzKk0Iz+Cp0bpyvsI="
```

### 导入重复设备

按 `name` 匹配:
- 如果设备名称已存在,更新该设备信息
- 如果设备名称不存在,添加新设备

## 常见问题(FAQ)

### Q: 设备文件保存在哪里?

**A**: 配置文件路径因平台而异:
- **Linux**: `~/.config/rustdesk/devices.json`
- **Windows**: `%APPDATA%/RustDesk/devices.json`
- **macOS**: `~/Library/Application Support/RustDesk/devices.json`

### Q: 如何批量导入设备?

**A**:
1. 准备JSON或CSV格式的设备清单
2. 运行: `rustdesk --import-devices devices.json`
3. 查看导入结果统计

### Q: 密码如何加密?

**A**:
- 导入时,明文密码自动使用RustDesk内置加密机制加密
- 加密后的密码以版本号开头(如 `00`)
- 重复导入已加密的密码不会重复加密

### Q: 如何区分ID连接和IP直连?

**A**:
- **IP直连**: 配置 `ip` 字段(非空),连接格式为 `ip:port`
- **ID连接**: 仅配置 `id` 字段,通过RustDesk中继服务器连接

### Q: 导入时重复设备如何处理?

**A**:
- 按 `name` 字段匹配
- 重复的设备会被**更新**(覆盖原有信息)
- 不重复的设备会被**新增**

### Q: 如何验证导入成功?

**A**:
```bash
# 1. 详细模式导入,查看输出
rustdesk --import-devices devices.json --verbose

# 2. 检查配置文件
cat ~/.config/rustdesk/devices.json  # Linux
type %APPDATA%\RustDesk\devices.json  # Windows
```

### Q: CSV文件中如何处理包含逗号的字段?

**A**: 使用双引号包裹:
```csv
name,note
Server1,"Production server, use with caution"
```

## 使用示例

### 示例1: IT管理员批量导入办公设备

```bash
# 1. 从Excel导出设备清单为CSV
# 2. 导入设备
rustdesk --import-devices office_devices.csv --verbose

# 输出:
# Importing devices from CSV: office_devices.csv
#   ✓ [NEW] Office-PC-01 (123456789)
#   ✓ [NEW] Office-PC-02 (234567890)
#   ...
# Summary:
#   Successfully imported: 50 (50 new, 0 updated)
```

### 示例2: 运维人员管理服务器

```json
{
    "devices": [
        {
            "name": "Prod-DB",
            "ip": "10.0.1.50",
            "port": 21119,
            "note": "Production database - read-only access"
        },
        {
            "name": "Dev-Server",
            "ip": "192.168.56.10",
            "port": 21118,
            "password": "devpass123"
        }
    ]
}
```

```bash
rustdesk --import-devices servers.json
```

### 示例3: 更新现有设备信息

```bash
# 第一次导入
rustdesk --import-devices devices.json
# ✓ Imported 5 devices (5 new, 0 updated)

# 修改devices.json中的设备信息后重新导入
rustdesk --import-devices devices.json
# ✓ Imported 5 devices (0 new, 5 updated)
```

## 下一步

设备列表功能的Flutter UI界面正在开发中,将提供:
- 可视化设备管理界面
- 搜索和过滤功能
- 一键连接按钮
- 面板折叠/展开
- 高度可调整

敬请期待!

---

**文档版本**: 1.0
**最后更新**: 2025-10-25
