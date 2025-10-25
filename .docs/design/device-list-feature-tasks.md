# RustDesk 设备列表功能 - 开发任务清单

**版本**: 1.0
**日期**: 2025-10-25
**关联文档**: [device-list-feature-design.md](./device-list-feature-design.md)

---

## 任务概览

**总估时**: 4-6天
**优先级**: P0 (核心功能)
**负责人**: 待分配

---

## 阶段划分

```
阶段1: Rust后端开发 (1-2天)
  └─→ 阶段2: Flutter数据模型 (0.5天)
        └─→ 阶段3: Flutter UI组件 (1-2天)
              └─→ 阶段4: 集成调试 (0.5天)
                    └─→ 阶段5: 测试验证 (0.5天)
                          └─→ 阶段6: 文档完善 (0.5天)
```

---

## 阶段1: Rust后端开发 (1-2天)

### 1.1 创建设备列表核心模块 - DeviceConfig

**文件**: `src/device_list.rs`

**开发任务**:
- [ ] 定义 `DeviceConfig` 结构体
  - [ ] 字段: name, id, ip, port, password, platform, note, username, hostname
  - [ ] 实现 Serialize/Deserialize trait

- [ ] 实现字段验证方法 `DeviceConfig::validate()`
  - [ ] name非空验证
  - [ ] id或ip至少一个非空验证
  - [ ] id格式验证 (如果非空)
  - [ ] port范围验证 (1-65535)

**单元测试** (在 `#[cfg(test)]` 模块中):
- [ ] 测试 `DeviceConfig::validate()` - 有效数据
  - [ ] 有效的ID连接设备 (id非空, ip为空)
  - [ ] 有效的IP连接设备 (ip非空, id为空)
  - [ ] 有效的混合设备 (id和ip都非空)

- [ ] 测试 `DeviceConfig::validate()` - 无效数据
  - [ ] name为空 -> 返回错误
  - [ ] id和ip都为空 -> 返回错误
  - [ ] id格式错误 -> 返回错误
  - [ ] port超出范围 (0, 65536) -> 返回错误

- [ ] 测试 `DeviceConfig` 序列化/反序列化
  - [ ] 结构体 -> JSON字符串
  - [ ] JSON字符串 -> 结构体
  - [ ] 往返序列化数据一致性

- [ ] 运行测试: `cargo test device_config`
- [ ] 确认编译通过,所有测试通过

---

### 1.2 创建设备列表核心模块 - DeviceListConfig

**文件**: `src/device_list.rs`

**开发任务**:
- [ ] 定义 `DeviceListConfig` 结构体
  - [ ] 字段: version, default_connection_mode, devices
  - [ ] 实现 Serialize/Deserialize trait
  - [ ] 实现默认值 (version="1.0", default_connection_mode="id")

**单元测试**:
- [ ] 测试空设备列表序列化/反序列化
- [ ] 测试包含多个设备的列表序列化/反序列化
- [ ] 测试默认字段值正确
- [ ] 运行测试: `cargo test device_list_config`
- [ ] 确认编译通过,所有测试通过

---

### 1.3 实现文件路径获取

**文件**: `src/device_list.rs`

**开发任务**:
- [ ] 实现 `get_device_list_path() -> PathBuf`
  - [ ] Linux: `~/.config/rustdesk/devices.json`
  - [ ] Windows: `%APPDATA%/RustDesk/devices.json`
  - [ ] macOS: `~/Library/Application Support/RustDesk/devices.json`
  - [ ] 使用 `hbb_common::config::Config::path()` 作为基础路径

**单元测试**:
- [ ] 测试 `get_device_list_path()` 返回路径格式正确
  - [ ] 路径包含正确的文件名 `devices.json`
  - [ ] 路径包含 RustDesk 配置目录
  - [ ] (可选) 使用条件编译测试不同平台

- [ ] 运行测试: `cargo test get_device_list_path`
- [ ] 确认编译通过,所有测试通过

---

### 1.4 实现设备列表加载功能

**文件**: `src/device_list.rs`

**开发任务**:
- [ ] 实现 `load_device_list() -> Result<DeviceListConfig, String>`
  - [ ] 获取文件路径
  - [ ] 读取JSON文件
  - [ ] 解析为 DeviceListConfig
  - [ ] 文件不存在时返回空配置
  - [ ] 错误处理

**单元测试** (使用 `tempfile` crate):
- [ ] 测试文件不存在
  - [ ] 返回空配置 (devices为空数组)
  - [ ] default_connection_mode为默认值

- [ ] 测试有效JSON文件
  - [ ] 正确加载设备列表
  - [ ] 所有字段正确解析

- [ ] 测试无效JSON文件
  - [ ] 格式错误 -> 返回错误信息
  - [ ] 缺少必填字段 -> 返回错误信息

- [ ] 运行测试: `cargo test load_device_list`
- [ ] 确认编译通过,所有测试通过

---

### 1.5 实现设备列表保存功能

**文件**: `src/device_list.rs`

**开发任务**:
- [ ] 实现 `save_device_list(config: &DeviceListConfig) -> Result<(), String>`
  - [ ] 获取文件路径
  - [ ] 序列化为JSON (pretty print, 缩进4空格)
  - [ ] 确保目录存在 (如果不存在则创建)
  - [ ] 写入文件
  - [ ] 错误处理

**单元测试** (使用 `tempfile` crate):
- [ ] 测试保存成功
  - [ ] 文件创建成功
  - [ ] JSON格式正确 (pretty print)
  - [ ] 再次加载数据一致

- [ ] 测试保存到不存在的目录
  - [ ] 自动创建目录
  - [ ] 文件保存成功

- [ ] 测试保存失败场景
  - [ ] (可选) 只读目录 -> 返回错误

- [ ] 运行测试: `cargo test save_device_list`
- [ ] 确认编译通过,所有测试通过

---

### 1.6 实现JSON解析功能

**文件**: `src/device_list.rs`

**开发任务**:
- [ ] 实现 `parse_json(content: &str) -> Result<Vec<DeviceConfig>, String>`
  - [ ] 解析JSON字符串
  - [ ] 提取devices数组 (支持完整格式和简化格式)
  - [ ] 返回设备向量
  - [ ] 错误处理

**单元测试**:
- [ ] 测试有效JSON - 完整格式
  - [ ] 单个设备
  - [ ] 多个设备
  - [ ] 包含所有字段

- [ ] 测试有效JSON - 简化格式
  - [ ] 仅包含必填字段 (name, id/ip)
  - [ ] 可选字段使用默认值

- [ ] 测试无效JSON
  - [ ] 格式错误的JSON字符串
  - [ ] 缺少devices数组
  - [ ] devices不是数组类型

- [ ] 测试字段类型错误
  - [ ] port为字符串 -> 解析错误
  - [ ] devices为对象 -> 解析错误

- [ ] 运行测试: `cargo test parse_json`
- [ ] 确认编译通过,所有测试通过

---

### 1.7 实现CSV解析功能

**文件**: `src/device_list.rs`

**依赖**:
- [ ] 在 `Cargo.toml` 中添加: `csv = "1.1"`

**开发任务**:
- [ ] 实现 `parse_csv(content: &str) -> Result<Vec<DeviceConfig>, String>`
  - [ ] 使用 `csv` crate解析
  - [ ] 读取表头,映射字段名
  - [ ] 字段映射到DeviceConfig
  - [ ] 跳过无效行,记录错误
  - [ ] 返回有效设备向量

**单元测试**:
- [ ] 测试有效CSV
  - [ ] 标准格式CSV (包含表头)
  - [ ] 多行设备数据
  - [ ] 空字段处理 (使用默认值)

- [ ] 测试无效CSV
  - [ ] 缺少表头 -> 返回错误
  - [ ] 列数不匹配 -> 跳过该行
  - [ ] 必填字段缺失 -> 跳过该行

- [ ] 测试特殊字符处理
  - [ ] 字段包含逗号 (用引号包裹)
  - [ ] 字段包含换行符 (用引号包裹)
  - [ ] 字段包含引号 (转义为双引号)

- [ ] 运行测试: `cargo test parse_csv`
- [ ] 确认编译通过,所有测试通过

---

### 1.8 实现密码加密功能

**文件**: `src/device_list.rs`

**开发任务**:
- [ ] 实现 `encrypt_password(password: &str) -> String`
  - [ ] 检测是否已加密 (以 "enc:" 开头)
  - [ ] 已加密 -> 直接返回
  - [ ] 未加密 -> 调用 RustDesk 加密函数
  - [ ] 空密码 -> 返回空字符串

**单元测试**:
- [ ] 测试明文密码加密
  - [ ] "password123" -> "enc:..."
  - [ ] 验证加密后以 "enc:" 开头
  - [ ] 验证加密后长度 > 原始长度

- [ ] 测试已加密密码不重复加密
  - [ ] "enc:abc123" -> "enc:abc123" (保持不变)

- [ ] 测试空密码
  - [ ] "" -> ""
  - [ ] 不调用加密函数

- [ ] 运行测试: `cargo test encrypt_password`
- [ ] 确认编译通过,所有测试通过

---

### 1.9 实现批量导入功能

**文件**: `src/device_list.rs`

**开发任务**:
- [ ] 实现 `import_devices(file_path: &str, verbose: bool, quiet: bool) -> Result<String, String>`
  - [ ] 读取文件内容
  - [ ] 根据扩展名选择解析器 (.json/.csv)
  - [ ] 解析设备列表
  - [ ] 验证每个设备 (调用 `validate()`)
  - [ ] 加密明文密码
  - [ ] 加载现有设备列表
  - [ ] 合并设备 (按name匹配,覆盖或新增)
  - [ ] 保存到文件
  - [ ] 生成输出摘要 (简洁/详细/静默模式)
  - [ ] 返回摘要字符串

**单元测试** (使用 `tempfile` crate):
- [ ] 测试JSON导入 - 新设备
  - [ ] 导入3个新设备
  - [ ] 验证全部添加成功
  - [ ] 验证密码已加密

- [ ] 测试JSON导入 - 重复设备
  - [ ] 现有2个设备,导入2个同名设备
  - [ ] 验证覆盖成功
  - [ ] 验证设备总数不变

- [ ] 测试JSON导入 - 混合场景
  - [ ] 现有2个设备,导入3个设备 (1个同名,2个新设备)
  - [ ] 验证1个更新,2个新增
  - [ ] 验证最终3个设备

- [ ] 测试CSV导入
  - [ ] 同JSON测试场景

- [ ] 测试验证和跳过
  - [ ] 导入包含无效设备 (name为空)
  - [ ] 跳过无效设备,仅导入有效设备
  - [ ] 返回正确的统计信息

- [ ] 测试输出格式
  - [ ] verbose模式 -> 返回详细信息
  - [ ] quiet模式 -> 返回空字符串
  - [ ] 默认模式 -> 返回摘要信息

- [ ] 测试错误处理
  - [ ] 文件不存在 -> 返回错误
  - [ ] 无效扩展名 -> 返回错误
  - [ ] 解析失败 -> 返回错误

- [ ] 运行测试: `cargo test import_devices`
- [ ] 确认编译通过,所有测试通过

---

### 1.10 添加FFI接口

**文件**: `src/flutter_ffi.rs` (或相应的FFI文件)

**开发任务**:
- [ ] 添加 `main_get_device_list() -> String`
  - [ ] 调用 `device_list::load_device_list()`
  - [ ] 序列化为JSON字符串返回
  - [ ] 错误处理,返回空JSON "{}"

- [ ] 添加 `main_save_device_list(json_str: String) -> String`
  - [ ] 解析JSON字符串为 `DeviceListConfig`
  - [ ] 调用 `device_list::save_device_list()`
  - [ ] 成功返回 "OK"
  - [ ] 失败返回错误信息

**测试** (集成测试):
- [ ] 测试 `main_get_device_list()` - 无设备
  - [ ] 返回空设备列表JSON

- [ ] 测试 `main_get_device_list()` - 有设备
  - [ ] 先保存设备列表
  - [ ] 调用FFI获取
  - [ ] 验证返回正确

- [ ] 测试 `main_save_device_list()` - 保存成功
  - [ ] 传入有效JSON
  - [ ] 返回 "OK"
  - [ ] 验证文件已保存

- [ ] 测试 `main_save_device_list()` - 保存失败
  - [ ] 传入无效JSON
  - [ ] 返回错误信息

- [ ] 运行测试: `cargo test ffi`
- [ ] 确认编译通过,所有测试通过

---

### 1.11 添加命令行参数处理

**文件**: `src/core_main.rs`

**开发任务**:
- [ ] 在 `CLI_COMMANDS` 数组中添加:
  - [ ] `"--devices"`
  - [ ] `"--import-devices"`
  - [ ] `"--verbose"`
  - [ ] `"--quiet"`

- [ ] 在 `core_main()` 函数中添加参数处理逻辑:
  - [ ] 解析 `--devices` -> 设置标志传递给Flutter
  - [ ] 解析 `--import-devices <file>` -> 调用 `import_devices()`
  - [ ] 解析 `--verbose` -> 设置详细输出标志
  - [ ] 解析 `--quiet` -> 设置静默模式标志
  - [ ] 打印导入结果 (如果不是quiet模式)

**测试** (手动测试,稍后集成测试覆盖):
- [ ] 编译项目: `cargo build`
- [ ] 创建测试文件 `test_devices.json`
- [ ] 测试导入: `./target/debug/rustdesk --import-devices test_devices.json`
- [ ] 测试详细模式: `./target/debug/rustdesk --import-devices test_devices.json --verbose`
- [ ] 测试静默模式: `./target/debug/rustdesk --import-devices test_devices.json --quiet`
- [ ] 验证输出格式正确

---

### 1.12 注册模块

**文件**: `src/lib.rs`

**开发任务**:
- [ ] 添加 `pub mod device_list;`

**测试**:
- [ ] 编译项目: `cargo build`
- [ ] 确认模块导入无错误
- [ ] 运行所有测试: `cargo test`

---

### 1.13 代码覆盖率验证

**任务清单**:
- [ ] 安装 tarpaulin: `cargo install cargo-tarpaulin`
- [ ] 运行所有测试: `cargo test`
- [ ] 生成覆盖率报告: `cargo tarpaulin --out Html --output-dir coverage`
- [ ] 打开 `coverage/index.html` 查看报告
- [ ] 验证 `device_list.rs` 覆盖率 >= 90%
- [ ] 识别未覆盖代码 (红色标记)
- [ ] 补充测试用例覆盖缺失代码
- [ ] 重新生成报告,确认达标

**测试工具依赖** (在 `Cargo.toml` 中添加):
```toml
[dev-dependencies]
tempfile = "3.8"  # 用于创建临时测试文件
```

---

### 1.14 集成测试 (手动验证)

**任务清单**:
- [ ] 创建测试文件 `test_devices.json` (包含3-5个设备)
- [ ] 创建测试文件 `test_devices.csv` (包含3-5个设备)
- [ ] 测试导入JSON: `cargo run -- --import-devices test_devices.json`
- [ ] 测试导入CSV: `cargo run -- --import-devices test_devices.csv`
- [ ] 测试详细模式: `cargo run -- --import-devices test_devices.json --verbose`
- [ ] 测试静默模式: `cargo run -- --import-devices test_devices.json --quiet`
- [ ] 验证生成的 `devices.json` 文件
  - [ ] 文件路径正确
  - [ ] JSON格式正确 (pretty print)
  - [ ] 设备数据完整
  - [ ] 密码已加密 (以 "enc:" 开头)
- [ ] 测试重复导入
  - [ ] 修改设备信息后重新导入
  - [ ] 验证设备信息已更新

---

## 阶段2: Flutter数据模型 (0.5天)

### 2.1 创建设备数据模型 - DeviceConfig

**文件**: `flutter/lib/models/device_list_model.dart`

**开发任务**:
- [ ] 创建 `DeviceConfig` 类
  - [ ] 字段定义 (name, id, ip, port, password, platform, note, username, hostname)
  - [ ] 实现 `fromJson()` 工厂构造函数
  - [ ] 实现 `toJson()` 方法
  - [ ] 实现 `displayTarget` getter (优先返回IP,否则返回ID)

**单元测试** (在 `flutter/test/models/device_list_model_test.dart`):
- [ ] 测试 `DeviceConfig.fromJson()` - 完整字段
  - [ ] 所有字段正确解析

- [ ] 测试 `DeviceConfig.fromJson()` - 最小字段
  - [ ] 仅name和id
  - [ ] 可选字段使用默认值

- [ ] 测试 `DeviceConfig.toJson()`
  - [ ] 往返序列化数据一致

- [ ] 测试 `displayTarget` getter
  - [ ] ip非空 -> 返回IP
  - [ ] ip为空,id非空 -> 返回ID
  - [ ] 都为空 -> 返回空字符串

- [ ] 运行测试: `cd flutter && flutter test test/models/device_list_model_test.dart`
- [ ] 确认所有测试通过

---

### 2.2 创建设备数据模型 - 搜索功能

**文件**: `flutter/lib/models/device_list_model.dart`

**开发任务**:
- [ ] 在 `DeviceConfig` 类中实现 `matchesSearch(String query)` 方法
  - [ ] 忽略大小写
  - [ ] 搜索字段: name, id, ip, platform, note, hostname
  - [ ] 任一字段匹配返回true

**单元测试**:
- [ ] 测试 `matchesSearch()` - 匹配name
  - [ ] 完全匹配
  - [ ] 部分匹配
  - [ ] 大小写不敏感

- [ ] 测试 `matchesSearch()` - 匹配IP
- [ ] 测试 `matchesSearch()` - 匹配ID
- [ ] 测试 `matchesSearch()` - 匹配note
- [ ] 测试 `matchesSearch()` - 不匹配
  - [ ] 返回false

- [ ] 运行测试: `cd flutter && flutter test`
- [ ] 确认所有测试通过

---

### 2.3 创建设备列表状态管理 - DeviceListModel

**文件**: `flutter/lib/models/device_list_model.dart`

**开发任务**:
- [ ] 创建 `DeviceListModel` 类 (继承 ChangeNotifier)
  - [ ] 私有字段:
    - [ ] `List<DeviceConfig> _allDevices = []`
    - [ ] `String _searchQuery = ""`
    - [ ] `String _defaultConnectionMode = "id"`

- [ ] 实现 Getter:
  - [ ] `List<DeviceConfig> devices` - 返回过滤后的设备列表
    - [ ] 如果 `_searchQuery` 为空,返回 `_allDevices`
    - [ ] 否则返回匹配搜索的设备

  - [ ] `String defaultConnectionMode` - 返回默认连接模式

- [ ] 实现 `updateSearch(String query)` 方法
  - [ ] 更新 `_searchQuery`
  - [ ] 调用 `notifyListeners()`

**单元测试**:
- [ ] 测试 `devices` getter - 无搜索
  - [ ] 返回所有设备

- [ ] 测试 `devices` getter - 有搜索
  - [ ] 仅返回匹配设备

- [ ] 测试 `updateSearch()` 方法
  - [ ] 触发 `notifyListeners()`
  - [ ] 过滤结果正确

- [ ] 运行测试: `cd flutter && flutter test`
- [ ] 确认所有测试通过

---

### 2.4 实现设备列表加载和保存

**文件**: `flutter/lib/models/device_list_model.dart`

**开发任务**:
- [ ] 实现 `Future<void> load()` 方法
  - [ ] 调用FFI: `bind.mainGetDeviceList()`
  - [ ] 解析JSON字符串
  - [ ] 更新 `_allDevices` 和 `_defaultConnectionMode`
  - [ ] 调用 `notifyListeners()`
  - [ ] 错误处理 (空字符串或无效JSON)

- [ ] 实现 `Future<void> save()` 方法
  - [ ] 构造 `DeviceListConfig` JSON
  - [ ] 调用FFI: `bind.mainSaveDeviceList(jsonStr)`
  - [ ] 错误处理

- [ ] 实现 `void addDevice(DeviceConfig device)` 方法
  - [ ] 添加到 `_allDevices`
  - [ ] 调用 `save()`
  - [ ] 调用 `notifyListeners()`

- [ ] 实现 `void removeDevice(String name)` 方法
  - [ ] 从 `_allDevices` 中移除
  - [ ] 调用 `save()`
  - [ ] 调用 `notifyListeners()`

**集成测试** (需要模拟FFI):
- [ ] 测试 `load()` - 空设备列表
- [ ] 测试 `load()` - 有效设备列表
- [ ] 测试 `save()` - 保存成功
- [ ] 测试 `addDevice()` - 添加新设备
- [ ] 测试 `removeDevice()` - 删除设备

- [ ] 运行测试: `cd flutter && flutter test`
- [ ] 确认所有测试通过

---

### 2.5 实现设备连接逻辑

**文件**: `flutter/lib/models/device_list_model.dart`

**开发任务**:
- [ ] 实现 `Future<void> connectDevice(DeviceConfig device, BuildContext context)` 方法
  - [ ] 判断 `device.ip` 是否非空
  - [ ] IP非空: 构造连接目标 `device.ip:device.port`
  - [ ] IP为空: 使用 `device.id`
  - [ ] 调用 RustDesk 连接函数 (参考现有连接逻辑)
  - [ ] 传递密码 (如果已保存)
  - [ ] 错误处理

**集成测试** (需要完整环境):
- [ ] 测试 IP 连接 (手动测试)
- [ ] 测试 ID 连接 (手动测试)
- [ ] 测试带密码连接 (手动测试)

---

## 阶段3: Flutter UI组件 (1-2天)

### 3.1 创建设备列表面板 - 基础结构

**文件**: `flutter/lib/desktop/widgets/device_list_panel.dart`

**开发任务**:
- [ ] 创建 `DeviceListPanel` StatefulWidget
  - [ ] 状态变量:
    - [ ] `bool _expanded = true` (折叠/展开状态)
    - [ ] `double _panelHeight = 150.0` (面板高度)
    - [ ] `TextEditingController _searchController` (搜索框控制器)

- [ ] 实现 `initState()`
  - [ ] 初始化搜索控制器
  - [ ] 加载设备列表: `Provider.of<DeviceListModel>(context, listen: false).load()`

- [ ] 实现 `dispose()`
  - [ ] 释放 `_searchController`

- [ ] 实现 `build()` 基础框架
  - [ ] 返回 `Column`: [DragableDivider, AnimatedContainer]
  - [ ] `AnimatedContainer` 高度根据 `_expanded` 状态切换
  - [ ] 动画时长: 200ms

**Widget测试**:
- [ ] 测试组件初始化
  - [ ] 默认展开状态
  - [ ] 默认高度150px

- [ ] 运行测试: `cd flutter && flutter test test/widgets/device_list_panel_test.dart`
- [ ] 确认编译通过,测试通过

---

### 3.2 创建设备列表面板 - 头部

**文件**: `flutter/lib/desktop/widgets/device_list_panel.dart`

**开发任务**:
- [ ] 实现 `Widget _buildPanelHeader()` 方法
  - [ ] 左侧: 图标 + 标题 "Device List"
  - [ ] 中间: 搜索框 (TextField)
    - [ ] 占位符: "Search devices..."
    - [ ] controller: `_searchController`
    - [ ] onChanged: 调用 `updateSearch()`
  - [ ] 右侧: 折叠/展开按钮 (IconButton)

- [ ] 实现搜索逻辑
  - [ ] 监听 `_searchController.onChanged`
  - [ ] 调用 `Provider.of<DeviceListModel>(context, listen: false).updateSearch(query)`

**Widget测试**:
- [ ] 测试搜索框输入
  - [ ] 输入文本触发过滤

- [ ] 测试折叠/展开按钮
  - [ ] 点击切换状态

- [ ] 运行测试: `cd flutter && flutter test`
- [ ] 确认测试通过

---

### 3.3 创建设备列表面板 - 设备表格

**文件**: `flutter/lib/desktop/widgets/device_list_panel.dart`

**开发任务**:
- [ ] 实现 `Widget _buildDeviceTable()` 方法
  - [ ] 使用 `Consumer<DeviceListModel>` 监听数据变化
  - [ ] 表头行: Name | IP/ID | Platform | Note | Action
  - [ ] 数据行: 遍历 `model.devices`, 调用 `_buildDeviceRow()`
  - [ ] 空状态: 显示 "No devices found"

- [ ] 实现 `Widget _buildDeviceRow(DeviceConfig device)` 方法
  - [ ] 名称列: `device.name`
  - [ ] IP/ID列: `device.displayTarget` (优先IP)
  - [ ] 平台列: 平台图标 + `device.platform`
  - [ ] 备注列: `device.note`
  - [ ] 操作列: [Connect] 按钮
    - [ ] onPressed: 调用 `model.connectDevice(device, context)`

**Widget测试**:
- [ ] 测试空状态显示
- [ ] 测试设备行渲染
  - [ ] 所有列正确显示

- [ ] 测试Connect按钮点击
  - [ ] 触发连接逻辑

- [ ] 运行测试: `cd flutter && flutter test`
- [ ] 确认测试通过

---

### 3.4 创建设备列表面板 - 交互功能

**文件**: `flutter/lib/desktop/widgets/device_list_panel.dart`

**开发任务**:
- [ ] 实现拖动调整高度逻辑
  - [ ] 在 `DragableDivider` 上添加 `onPointerMove` 监听
  - [ ] 根据拖动距离更新 `_panelHeight`
  - [ ] 限制高度范围: 80px - 400px
  - [ ] 调用 `setState()` 更新UI

- [ ] 实现折叠/展开逻辑
  - [ ] 点击折叠按钮: 设置 `_expanded = false`, 高度为0
  - [ ] 点击展开按钮: 设置 `_expanded = true`, 高度为 `_panelHeight`
  - [ ] 使用 `AnimatedContainer` 平滑过渡

**Widget测试**:
- [ ] 测试拖动调整高度
  - [ ] 模拟拖动事件
  - [ ] 验证高度更新

- [ ] 测试折叠/展开动画
  - [ ] 点击按钮后验证状态变化

- [ ] 运行测试: `cd flutter && flutter test`
- [ ] 确认测试通过

---

### 3.5 修改远程窗口布局

**文件**: `flutter/lib/desktop/pages/remote_tab_page.dart`

**开发任务**:
- [ ] 在 `_ConnectionTabPageState` 中添加:
  - [ ] `final bool _showDeviceList = true;`

- [ ] 修改 `build()` 方法
  - [ ] 原布局包裹在 `Expanded` 中
  - [ ] 返回 `Column([Expanded(原布局), if(_showDeviceList) DeviceListPanel()])`

- [ ] 实现 `_buildMainContent()` 方法
  - [ ] 判断是否有打开的标签
  - [ ] 无标签: 返回 `_buildWelcomePage()`
  - [ ] 有标签: 返回原有的 `DesktopTab` 布局

- [ ] 实现 `Widget _buildWelcomePage()` 方法
  - [ ] Center对齐
  - [ ] Column布局:
    - [ ] 设备图标 (Icon, size: 64)
    - [ ] 标题: "Welcome to RustDesk Device Manager"
    - [ ] 提示: "Select a device from the list below to connect"
    - [ ] 向下箭头图标

**集成测试**:
- [ ] 编译并运行: `cd flutter && flutter run`
- [ ] 验证布局正确
  - [ ] 设备列表在底部显示
  - [ ] 欢迎页在无标签时显示

- [ ] 确认编译通过

---

### 3.6 修改应用启动逻辑

**文件**: `flutter/lib/main.dart`

**开发任务**:
- [ ] 在 `App` widget中注册 `DeviceListModel` Provider
  - [ ] 在 `MultiProvider` 的 `providers` 列表中添加:
  - [ ] `ChangeNotifierProvider(create: (_) => DeviceListModel())`

- [ ] 在 `main()` 函数中添加 `--devices` 参数处理
  - [ ] 解析命令行参数: `args.contains('--devices')`
  - [ ] 如果包含: 调用 `runDeviceListWindow()`
  - [ ] 否则: 正常启动

- [ ] 实现 `Future<void> runDeviceListWindow()` 函数
  - [ ] 初始化环境: `await initEnv(kAppTypeDesktopRemote)`
  - [ ] 构造空参数: `id=null` (触发欢迎页)
  - [ ] 调用 `runApp(App())`
  - [ ] 设置窗口标题: "RustDesk - Device Manager"
  - [ ] 设置窗口大小: 1000x700

**集成测试**:
- [ ] 测试正常启动: `cargo run`
  - [ ] 不显示设备列表面板

- [ ] 测试设备管理窗口启动: `cargo run -- --devices`
  - [ ] 显示设备管理窗口
  - [ ] 显示欢迎页
  - [ ] 显示设备列表面板

- [ ] 确认编译通过,功能正常

---

### 3.7 UI集成测试

**任务清单**:
- [ ] 启动设备管理窗口: `cargo run -- --devices`

- [ ] 验证基础UI
  - [ ] 欢迎页正常显示
  - [ ] 设备列表面板正常显示
  - [ ] 搜索框可见

- [ ] 测试搜索功能
  - [ ] 输入关键词
  - [ ] 设备列表实时过滤
  - [ ] 清空关键词,恢复所有设备

- [ ] 测试折叠/展开
  - [ ] 点击折叠按钮,面板收起
  - [ ] 点击展开按钮,面板展开
  - [ ] 动画平滑

- [ ] 测试拖动调整高度
  - [ ] 拖动分隔条
  - [ ] 面板高度跟随鼠标
  - [ ] 高度限制在80-400px之间

- [ ] 测试连接按钮
  - [ ] 点击Connect按钮
  - [ ] 新标签页打开
  - [ ] 欢迎页隐藏,显示远程桌面

---

## 阶段4: 集成调试 (0.5天)

### 4.1 端到端测试 - 导入和显示

**前置条件**:
- [ ] 创建测试文件 `test_devices.json` (包含3个设备)
- [ ] 创建测试文件 `test_devices.csv` (包含3个设备)

**测试步骤**:
- [ ] 测试JSON导入并在UI显示
  - [ ] 运行: `cargo run -- --import-devices test_devices.json`
  - [ ] 验证导入成功输出
  - [ ] 运行: `cargo run -- --devices`
  - [ ] 验证UI显示3个设备
  - [ ] 验证设备信息正确 (name, ip, id, platform, note)

- [ ] 测试CSV导入并在UI显示
  - [ ] 运行: `cargo run -- --import-devices test_devices.csv`
  - [ ] 验证导入成功输出
  - [ ] 运行: `cargo run -- --devices`
  - [ ] 验证UI显示设备

- [ ] 修复发现的问题
- [ ] 重新测试直到通过

---

### 4.2 端到端测试 - 连接功能

**测试步骤**:
- [ ] 测试ID连接方式
  - [ ] 创建设备: id非空, ip为空
  - [ ] 点击Connect按钮
  - [ ] 验证使用ID连接
  - [ ] 验证新标签页打开

- [ ] 测试IP直连方式
  - [ ] 创建设备: ip非空
  - [ ] 点击Connect按钮
  - [ ] 验证使用IP直连 (格式: ip:port)
  - [ ] 验证新标签页打开

- [ ] 测试密码自动填充
  - [ ] 创建设备: password已加密
  - [ ] 点击Connect
  - [ ] 验证密码自动填充,无需手动输入

- [ ] 测试密码提示输入
  - [ ] 创建设备: password为空
  - [ ] 点击Connect
  - [ ] 验证提示输入密码

- [ ] 修复发现的问题
- [ ] 重新测试直到通过

---

### 4.3 跨平台测试

**macOS平台** (当前环境):
- [ ] 验证配置文件路径
  - [ ] 运行导入命令
  - [ ] 检查文件: `~/Library/Application Support/RustDesk/devices.json`
  - [ ] 验证文件存在且格式正确

- [ ] 验证导入导出功能
  - [ ] 导入JSON: ✓
  - [ ] 导入CSV: ✓
  - [ ] UI加载: ✓

- [ ] 验证UI显示正常
  - [ ] 启动设备管理窗口
  - [ ] 所有UI元素正常渲染
  - [ ] 无布局错误

**Windows平台** (如可用):
- [ ] 验证配置文件路径 (`%APPDATA%/RustDesk/devices.json`)
- [ ] 验证导入导出功能
- [ ] 验证UI显示正常

**Linux平台** (如可用):
- [ ] 验证配置文件路径 (`~/.config/rustdesk/devices.json`)
- [ ] 验证导入导出功能
- [ ] 验证UI显示正常

---

### 4.4 错误处理测试

**测试步骤**:
- [ ] 测试导入无效JSON文件
  - [ ] 创建 `invalid.json` (格式错误)
  - [ ] 运行: `cargo run -- --import-devices invalid.json`
  - [ ] 验证返回错误信息,不崩溃

- [ ] 测试导入无效CSV文件
  - [ ] 创建 `invalid.csv` (缺少表头)
  - [ ] 运行导入命令
  - [ ] 验证返回错误信息,不崩溃

- [ ] 测试导入缺少必填字段的设备
  - [ ] 创建JSON: 设备缺少name
  - [ ] 运行导入
  - [ ] 验证跳过该设备,输出警告

- [ ] 测试导入重复名称的设备
  - [ ] 导入2次相同设备
  - [ ] 验证第二次覆盖第一次
  - [ ] 验证设备总数正确

- [ ] 测试配置文件损坏恢复
  - [ ] 手动破坏 `devices.json` 文件
  - [ ] 启动设备管理窗口
  - [ ] 验证返回空设备列表,不崩溃

- [ ] 修复发现的问题
- [ ] 重新测试直到所有错误处理正确

---

## 阶段5: 测试验证 (0.5天)

### 5.1 功能测试用例执行

**测试用例清单** (每个用例执行后记录结果):

- [ ] **TC-001: 导入JSON格式设备列表**
  - [ ] 步骤: 运行 `cargo run -- --import-devices test.json`
  - [ ] 预期: 成功导入,输出摘要
  - [ ] 结果: ______ (Pass/Fail)
  - [ ] 备注: ______

- [ ] **TC-002: 导入CSV格式设备列表**
  - [ ] 步骤: 运行 `cargo run -- --import-devices test.csv`
  - [ ] 预期: 成功导入,输出摘要
  - [ ] 结果: ______ (Pass/Fail)

- [ ] **TC-003: 通过ID连接设备**
  - [ ] 步骤: UI点击ID设备的Connect按钮
  - [ ] 预期: 使用ID连接,新标签打开
  - [ ] 结果: ______ (Pass/Fail)

- [ ] **TC-004: 通过IP直连设备**
  - [ ] 步骤: UI点击IP设备的Connect按钮
  - [ ] 预期: 使用IP:port直连,新标签打开
  - [ ] 结果: ______ (Pass/Fail)

- [ ] **TC-005: 搜索设备 (按名称)**
  - [ ] 步骤: 输入设备名称关键词
  - [ ] 预期: 实时过滤,仅显示匹配设备
  - [ ] 结果: ______ (Pass/Fail)

- [ ] **TC-006: 搜索设备 (按IP)**
  - [ ] 步骤: 输入IP地址关键词
  - [ ] 预期: 实时过滤,显示IP匹配设备
  - [ ] 结果: ______ (Pass/Fail)

- [ ] **TC-007: 搜索设备 (按备注)**
  - [ ] 步骤: 输入备注关键词
  - [ ] 预期: 实时过滤,显示备注匹配设备
  - [ ] 结果: ______ (Pass/Fail)

- [ ] **TC-008: 面板折叠/展开**
  - [ ] 步骤: 点击折叠/展开按钮
  - [ ] 预期: 面板平滑动画折叠/展开
  - [ ] 结果: ______ (Pass/Fail)

- [ ] **TC-009: 拖动调整面板高度**
  - [ ] 步骤: 拖动分隔条
  - [ ] 预期: 面板高度跟随,限制80-400px
  - [ ] 结果: ______ (Pass/Fail)

- [ ] **TC-010: 重启应用,面板状态保持**
  - [ ] 步骤: 调整面板高度,关闭后重启
  - [ ] 预期: 面板高度保持 (如果实现了持久化)
  - [ ] 结果: ______ (Pass/Fail)
  - [ ] 备注: MVP可不实现持久化

- [ ] **TC-011: 密码自动加密**
  - [ ] 步骤: 导入明文密码设备
  - [ ] 预期: 查看devices.json,密码以"enc:"开头
  - [ ] 结果: ______ (Pass/Fail)

- [ ] **TC-012: 已加密密码不重复加密**
  - [ ] 步骤: 导入已加密密码设备
  - [ ] 预期: 密码保持不变
  - [ ] 结果: ______ (Pass/Fail)

**测试总结**:
- [ ] 通过用例数: ______ / 12
- [ ] 失败用例数: ______
- [ ] 阻塞问题数: ______

---

### 5.2 性能测试

**准备工作**:
- [ ] 生成性能测试数据
  - [ ] 创建 `perf_test_100.json` (100个设备)
  - [ ] 创建 `perf_test_1000.json` (1000个设备)

**测试步骤**:
- [ ] **PT-001: 导入100个设备**
  - [ ] 运行: `time cargo run -- --import-devices perf_test_100.json`
  - [ ] 预期: 响应时间 < 1秒
  - [ ] 实际耗时: ______ 秒
  - [ ] 结果: ______ (Pass/Fail)

- [ ] **PT-002: 导入1000个设备**
  - [ ] 运行: `time cargo run -- --import-devices perf_test_1000.json`
  - [ ] 预期: 响应时间 < 5秒
  - [ ] 实际耗时: ______ 秒
  - [ ] 结果: ______ (Pass/Fail)

- [ ] **PT-003: 搜索1000个设备**
  - [ ] 加载1000个设备后,输入搜索关键词
  - [ ] 预期: 响应时间 < 100ms (主观感受流畅)
  - [ ] 实际体验: ______ (流畅/卡顿)
  - [ ] 结果: ______ (Pass/Fail)

- [ ] **PT-004: UI渲染1000个设备**
  - [ ] 启动设备管理窗口,加载1000设备
  - [ ] 预期: 无卡顿,滚动流畅
  - [ ] 实际体验: ______ (流畅/卡顿)
  - [ ] 结果: ______ (Pass/Fail)
  - [ ] 备注: 如有性能问题,考虑虚拟滚动

**性能优化** (如果测试不通过):
- [ ] 识别性能瓶颈
- [ ] 实施优化 (例如: 虚拟滚动, 延迟加载)
- [ ] 重新测试验证

---

### 5.3 安全测试

**测试步骤**:
- [ ] **ST-001: 验证密码加密存储**
  - [ ] 导入包含明文密码的设备
  - [ ] 打开 `devices.json` 文件
  - [ ] 验证密码字段以 "enc:" 开头
  - [ ] 验证无法直接看到明文
  - [ ] 结果: ______ (Pass/Fail)

- [ ] **ST-002: 验证密码不在UI显示**
  - [ ] 启动设备管理窗口
  - [ ] 查看设备表格
  - [ ] 验证密码列不存在或显示为 "******"
  - [ ] 结果: ______ (Pass/Fail)

- [ ] **ST-003: 验证配置文件权限**
  - [ ] 运行: `ls -la ~/Library/Application\ Support/RustDesk/devices.json`
  - [ ] 验证权限为 `-rw-------` (600) 或 `-rw-r--r--` (644)
  - [ ] 验证仅当前用户可写
  - [ ] 结果: ______ (Pass/Fail)
  - [ ] 备注: 文件权限由系统默认控制

**安全问题修复** (如果发现问题):
- [ ] 记录安全问题
- [ ] 实施修复
- [ ] 重新测试验证

---

## 阶段6: 文档完善 (0.5天)

### 6.1 创建示例文件

**文件**: `docs/examples/devices.json`

**开发任务**:
- [ ] 创建JSON示例文件
  - [ ] 包含5个示例设备:
    - [ ] 1个ID连接设备 (ip为空)
    - [ ] 1个IP直连设备 (ip非空)
    - [ ] 1个混合设备 (id和ip都有)
    - [ ] 1个带密码设备 (password已加密)
    - [ ] 1个无密码设备 (password为空)
  - [ ] 包含所有字段示例
  - [ ] 格式化为pretty print (4空格缩进)

**验证**:
- [ ] 使用示例文件导入: `cargo run -- --import-devices docs/examples/devices.json`
- [ ] 验证导入成功
- [ ] 验证UI正确显示

---

### 6.2 创建CSV示例文件

**文件**: `docs/examples/devices.csv`

**开发任务**:
- [ ] 创建CSV示例文件
  - [ ] 表头: `name,id,ip,port,password,platform,note,username,hostname`
  - [ ] 包含与JSON相同的5个示例设备
  - [ ] 测试特殊字符 (逗号, 引号)

**验证**:
- [ ] 使用示例文件导入: `cargo run -- --import-devices docs/examples/devices.csv`
- [ ] 验证导入成功
- [ ] 验证数据与JSON一致

---

### 6.3 编写用户文档

**文件**: `docs/device-list-usage.md`

**开发任务**:
- [ ] 编写功能介绍章节
  - [ ] 设备列表功能概述
  - [ ] 主要特性 (导入, 搜索, 连接)
  - [ ] 使用场景

- [ ] 编写配置文件格式说明
  - [ ] JSON格式结构
  - [ ] CSV格式结构
  - [ ] 字段说明表格
  - [ ] 必填/可选字段标注

- [ ] 编写命令行使用指南
  - [ ] `--devices` 参数说明和示例
  - [ ] `--import-devices <file>` 参数说明和示例
  - [ ] `--verbose` 和 `--quiet` 参数说明
  - [ ] 完整命令示例

- [ ] 编写UI操作指南
  - [ ] 启动设备管理窗口
  - [ ] 搜索设备 (附截图)
  - [ ] 连接设备 (附截图)
  - [ ] 面板折叠/展开
  - [ ] 拖动调整高度

- [ ] 编写常见问题 (FAQ)
  - [ ] Q: 设备文件保存在哪里?
  - [ ] Q: 如何批量导入设备?
  - [ ] Q: 密码如何加密?
  - [ ] Q: 如何区分ID连接和IP直连?
  - [ ] Q: 导入时重复设备如何处理?

**验证**:
- [ ] 文档格式正确 (Markdown语法)
- [ ] 所有示例命令可执行
- [ ] 所有截图清晰可见

---

### 6.4 更新README和帮助信息

**文件**: `README.md`

**开发任务**:
- [ ] 在README.md中添加设备列表功能说明
  - [ ] 在Features章节添加"Device List Management"
  - [ ] 简要介绍功能
  - [ ] 链接到完整文档 `docs/device-list-usage.md`

**文件**: `src/core_main.rs`

**开发任务**:
- [ ] 更新 `--help` 输出
  - [ ] 添加 `--devices` 参数说明
  - [ ] 添加 `--import-devices <file>` 参数说明
  - [ ] 添加 `--verbose` 和 `--quiet` 参数说明

**验证**:
- [ ] 运行: `cargo run -- --help`
- [ ] 验证新参数显示在帮助信息中
- [ ] 验证描述准确清晰

---

### 6.5 添加架构图到文档

**文件**: `.docs/design/device-list-feature-design.md`

**开发任务**:
- [ ] 确认架构图已包含在设计文档中
- [ ] (可选) 导出架构图为PNG/SVG
- [ ] (可选) 在用户文档中引用架构图

**文件**: `docs/device-list-usage.md`

**开发任务**:
- [ ] (可选) 添加简化版架构图
- [ ] 标注用户交互流程

---

## 验收标准

### 功能验收

- [ ] 所有P0功能正常工作
- [ ] 命令行导入JSON/CSV成功
- [ ] UI面板正常显示和交互
- [ ] ID连接和IP直连都能正常工作
- [ ] 搜索过滤功能正常
- [ ] 密码加密存储正常

### 质量验收

- [ ] 跨平台测试通过 (Windows/Linux/macOS)
- [ ] 性能测试达标 (1000设备,搜索<100ms)
- [ ] 无严重Bug和内存泄漏
- [ ] 代码通过Code Review
- [ ] 用户文档和示例完整

### 交付物

- [ ] 源代码 (已合并到主分支)
- [ ] 设计文档 (device-list-feature-design.md)
- [ ] 任务清单 (本文档)
- [ ] 用户文档 (device-list-usage.md)
- [ ] 示例文件 (devices.json, devices.csv)
- [ ] 测试报告

---

## 风险与依赖

### 技术风险

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| FFI通信异常 | 功能无法工作 | 增加错误处理和日志,充分测试 |
| CSV解析性能问题 | 大文件导入慢 | 使用高效的csv crate,必要时异步处理 |
| 跨平台路径差异 | 配置文件读写失败 | 使用标准库API,充分跨平台测试 |
| 密码加密机制变更 | 导入密码无法使用 | 预留版本号,支持多版本兼容 |

### 外部依赖

- [ ] `csv` crate (Rust依赖)
- [ ] `DragableDivider` 组件 (Flutter,需确认存在)
- [ ] RustDesk现有加密机制 (`encrypt_str_or_original`)
- [ ] RustDesk现有连接函数 (`connect()`)

---

## 进度跟踪

**开始日期**: ____________
**预计完成日期**: ____________
**实际完成日期**: ____________

### 每日进度

| 日期 | 完成任务 | 遇到的问题 | 解决方案 | 明日计划 |
|------|---------|-----------|---------|---------|
| Day 1 |  |  |  |  |
| Day 2 |  |  |  |  |
| Day 3 |  |  |  |  |
| Day 4 |  |  |  |  |
| Day 5 |  |  |  |  |
| Day 6 |  |  |  |  |

---

**文档结束**

---

**审阅签名**:

- [ ] 技术负责人: ____________  日期: ______
- [ ] 开发工程师: ____________  日期: ______
- [ ] 测试工程师: ____________  日期: ______
