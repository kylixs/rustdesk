# RustDesk 设备列表功能 - 集成指南

**日期**: 2025-10-25
**状态**: 开发完成,待集成
**版本**: 1.0

---

## 开发完成情况

### ✅ 已完成模块

#### 1. Rust后端 (100%完成)
- ✅ `src/device_list.rs` - 核心逻辑模块
- ✅ `src/flutter_ffi.rs` - FFI接口
- ✅ `src/core_main.rs` - 命令行参数
- ✅ 6个单元测试全部通过
- ✅ JSON/CSV导入功能已验证

#### 2. Flutter数据模型 (100%完成)
- ✅ `flutter/lib/models/device_list_model.dart`
  - `DeviceConfig` 类 - 设备配置数据模型
  - `DeviceListConfig` 类 - 设备列表配置
  - `DeviceListModel` 类 - 状态管理(ChangeNotifier)

#### 3. Flutter UI组件 (100%完成)
- ✅ `flutter/lib/desktop/widgets/device_list_panel.dart`
  - 设备列表面板主组件
  - 搜索功能
  - 设备表格
  - 折叠/展开功能
  - 高度可调整(使用DraggableDivider)

---

## 集成步骤

### 步骤1: 注册Provider

在 `flutter/lib/main.dart` 中注册 `DeviceListModel`:

```dart
import 'package:flutter_hbb/models/device_list_model.dart';

// 在MultiProvider的providers列表中添加
MultiProvider(
  providers: [
    // ... 现有providers ...
    ChangeNotifierProvider(create: (_) => DeviceListModel()),
  ],
  child: MyApp(),
)
```

### 步骤2: 更新FFI绑定

在 `flutter/lib/models/device_list_model.dart` 中更新FFI调用:

```dart
// 将placeholder替换为实际的FFI调用
Future<String> _getDeviceListFromFFI() async {
  return await bind.mainGetDeviceList();
}

Future<String> _saveDeviceListToFFI(String jsonStr) async {
  return await bind.mainSaveDeviceList(jsonStr: jsonStr);
}
```

### 步骤3: 集成到远程窗口 (可选方案)

#### 方案A: 添加到ConnectionTabPage底部

修改 `flutter/lib/desktop/pages/remote_tab_page.dart`:

```dart
import 'package:flutter_hbb/desktop/widgets/device_list_panel.dart';

@override
Widget build(BuildContext context) {
  final child = Scaffold(
    backgroundColor: Theme.of(context).colorScheme.background,
    body: Column(  // 改为Column
      children: [
        Expanded(  // 原有的DesktopTab
          child: DesktopTab(
            controller: tabController,
            onWindowCloseButton: handleWindowCloseButton,
            // ... 其他参数 ...
          ),
        ),
        // 添加设备列表面板
        const DeviceListPanel(),
      ],
    ),
  );

  // ... 其余代码 ...
}
```

#### 方案B: 独立的设备管理窗口

创建 `flutter/lib/desktop/pages/device_manager_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/widgets/device_list_panel.dart';

class DeviceManagerPage extends StatelessWidget {
  const DeviceManagerPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Manager'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.devices,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Welcome to RustDesk Device Manager',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Select a device from the list below to connect',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const DeviceListPanel(),
        ],
      ),
    );
  }
}
```

### 步骤4: 处理--devices命令行参数

在 `flutter/lib/main.dart` 的启动逻辑中:

```dart
// 检查命令行参数
final args = await getCommandLineArgs();
if (args.contains('--devices')) {
  runApp(
    MultiProvider(
      providers: [...],
      child: MaterialApp(
        home: DeviceManagerPage(),
      ),
    ),
  );
  return;
}
```

### 步骤5: 实现连接逻辑

在 `DeviceListModel.connectDevice()` 方法中调用实际的连接函数:

```dart
Future<void> connectDevice(DeviceConfig device) async {
  try {
    final (target, isIpConnection) = device.connectionTarget;

    // 调用RustDesk的连接函数
    // 方案1: 如果有现成的连接函数
    await bind.mainConnect(
      id: target,
      password: device.password,
    );

    // 方案2: 如果需要区分IP和ID连接
    if (isIpConnection) {
      // IP直连
      await bind.mainConnectDirect(
        address: target,
        password: device.password,
      );
    } else {
      // ID连接
      await bind.mainConnect(
        id: target,
        password: device.password,
      );
    }
  } catch (e) {
    debugPrint('Failed to connect to device ${device.name}: $e');
    rethrow;
  }
}
```

---

## 测试步骤

### 1. 编译测试

```bash
# 编译Flutter项目
cd flutter
flutter pub get
flutter build windows  # 或 linux, macos
```

### 2. 导入测试数据

```bash
# 导入示例设备
cargo run --bin rustdesk -- --import-devices docs/examples/devices.json --verbose
```

### 3. 启动设备管理窗口

```bash
# 方案A: 独立窗口
cargo run --bin rustdesk -- --devices

# 方案B: 连接时显示
# 在remote_tab_page集成后,连接远程桌面时会在底部显示设备列表
```

### 4. 功能测试清单

- [ ] 设备列表正常加载
- [ ] 搜索框实时过滤
- [ ] 设备信息正确显示(名称、IP/ID、平台、备注)
- [ ] 点击Connect按钮可以连接
- [ ] 面板可以折叠/展开
- [ ] 面板高度可以拖动调整
- [ ] 刷新按钮正常工作

---

## 配置和自定义

### 自定义样式

在 `device_list_panel.dart` 中可以调整:

```dart
// 面板高度范围
static const double minHeight = 80.0;
static const double maxHeight = 400.0;
static const double headerHeight = 40.0;

// 默认高度
double _panelHeight = 150.0;
```

### 持久化面板状态

可以使用SharedPreferences保存面板高度和展开状态:

```dart
import 'package:shared_preferences/shared_preferences.dart';

// 保存状态
Future<void> _savePanelState() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setDouble('device_panel_height', _panelHeight);
  await prefs.setBool('device_panel_expanded', _expanded);
}

// 加载状态
Future<void> _loadPanelState() async {
  final prefs = await SharedPreferences.getInstance();
  setState(() {
    _panelHeight = prefs.getDouble('device_panel_height') ?? 150.0;
    _expanded = prefs.getBool('device_panel_expanded') ?? true;
  });
}
```

---

## 已知问题和注意事项

### 1. FFI绑定

当前FFI方法是placeholder,需要根据实际的flutter_rust_bridge配置更新:

```dart
// 可能需要重新生成FFI绑定
flutter_rust_bridge_codegen \
  --rust-input src/flutter_ffi.rs \
  --dart-output flutter/lib/bridge_generated.dart
```

### 2. 连接逻辑

`connectDevice` 方法当前只是占位符,需要调用实际的RustDesk连接函数。

可以参考现有的连接代码,如 `flutter/lib/desktop/pages/remote_page.dart` 中的连接逻辑。

### 3. 平台兼容性

- 设备列表功能仅支持桌面平台(Windows/Linux/macOS)
- Android和iOS已提供stub实现,调用时返回空数据

### 4. 性能优化

对于大量设备(1000+),考虑:
- 使用虚拟滚动 (`ListView.builder` 已使用)
- 分页加载
- 延迟加载设备详情

---

## 文件清单

### Rust后端
- [x] `src/device_list.rs` (500行)
- [x] `src/flutter_ffi.rs` (修改,+60行)
- [x] `src/core_main.rs` (修改,+35行)
- [x] `src/lib.rs` (修改,+3行)
- [x] `Cargo.toml` (修改,+3行依赖)

### Flutter前端
- [x] `flutter/lib/models/device_list_model.dart` (350行)
- [x] `flutter/lib/desktop/widgets/device_list_panel.dart` (450行)
- [ ] `flutter/lib/main.dart` (待修改,注册Provider)
- [ ] `flutter/lib/desktop/pages/remote_tab_page.dart` (待修改,集成面板)

### 文档和示例
- [x] `docs/DEVICE_LIST_USAGE.md`
- [x] `docs/DEVICE_LIST_INTEGRATION.md` (本文档)
- [x] `docs/examples/devices.json`
- [x] `docs/examples/devices.csv`
- [x] `.docs/design/device-list-feature-design.md`
- [x] `.docs/design/device-list-feature-tasks.md`
- [x] `.docs/design/device-list-test-report.md`

### 测试文件
- [x] `test_devices.json`
- [x] `test_devices.csv`

---

## 下一步建议

### 立即可做
1. ✅ Rust后端功能已完整,可以直接使用命令行导入
2. ✅ Flutter组件已完成,可以作为独立widget使用

### 需要集成工作
1. 在 `main.dart` 注册 `DeviceListModel` Provider
2. 在 `remote_tab_page.dart` 或创建独立页面集成UI
3. 更新FFI绑定(如果使用自动生成)
4. 实现实际的连接逻辑

### 可选增强功能
1. 添加设备编辑/删除UI(当前只能通过命令行)
2. 添加设备分组功能
3. 添加在线状态检测
4. 添加右键菜单(文件传输、终端等)
5. 从通讯录导入设备

---

## 快速集成示例

最简单的集成方式(用于测试):

**1. 修改 `flutter/lib/main.dart`:**

```dart
import 'package:flutter_hbb/models/device_list_model.dart';

// 在main()函数中
runApp(
  MultiProvider(
    providers: [
      // ... 现有providers ...
      ChangeNotifierProvider(create: (_) => DeviceListModel()),
    ],
    child: MyApp(),
  ),
);
```

**2. 创建测试页面 `flutter/lib/desktop/pages/device_test_page.dart`:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/widgets/device_list_panel.dart';

class DeviceTestPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Device List Test')),
      body: DeviceListPanel(),
    );
  }
}
```

**3. 在路由中添加测试页面,启动查看效果**

---

## 联系和支持

如有问题,请参考:
- 设计文档: `.docs/design/device-list-feature-design.md`
- 使用文档: `docs/DEVICE_LIST_USAGE.md`
- 测试报告: `.docs/design/device-list-test-report.md`

---

**文档版本**: 1.0
**最后更新**: 2025-10-25
**状态**: 待集成
