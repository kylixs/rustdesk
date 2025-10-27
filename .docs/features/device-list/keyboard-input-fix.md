# 设备管理窗口键盘输入问题修复报告

## 问题描述

在设备管理窗口(`--devices`模式)中,当用户连接到远程设备后,键盘输入无法传递到远程系统。所有按键事件被阻止,导致无法在远程桌面上进行任何文字输入操作。

## 问题诊断

### 诊断方法

为了定位问题,在键盘事件处理链路的5个关键阶段添加了详细的诊断日志:

1. **STAGE-1: UI事件接收** (`flutter/lib/common/widgets/remote_input.dart`)
   - 位置: `RawKeyFocusScope.onKeyEvent` 回调
   - 记录: 事件类型、字符、逻辑键、物理键、焦点状态

2. **STAGE-2: Input Model处理** (`flutter/lib/models/input_model.dart:555-579`)
   - 位置: `InputModel.handleKeyEvent()` 方法
   - 记录: 输入源状态、视图模式、平台类型、阻止原因

3. **STAGE-3: 路由决策** (`flutter/lib/models/input_model.dart`)
   - 位置: 键盘模式分支判断
   - 记录: 路由到新键盘模式或遗留键盘模式

4. **STAGE-4: FFI参数准备** (`flutter/lib/models/input_model.dart`)
   - 位置: `newKeyboardMode()` 或 `legacyKeyboardMode()` 方法
   - 记录: 字符、USB HID码、锁定模式状态

5. **STAGE-5: FFI桥接调用** (`flutter/lib/models/input_model.dart`)
   - 位置: `bind.sessionHandleFlutterKeyEvent()` 调用后
   - 记录: FFI调用完成确认

### 诊断结果

通过分析诊断日志 (`key_diagnostic_enhanced.log`),发现问题出现在 **STAGE-2**:

```
flutter: [KEY_DIAG] [STAGE-1:UI_EVENT] type=KeyDownEvent, char="k", logical=K, physical=0x0007000e, hasFocus=true
flutter: [KEY_DIAG] [STAGE-2:INPUT_MODEL] char="k", viewOnly=false, viewCamera=false
flutter: [KEY_DIAG] [STAGE-2:INPUT_SOURCE] actualValue="Input source 1", isInputSourceFlutter=false, platform=desktop
flutter: [KEY_DIAG] [STAGE-2:BLOCKED] Blocked by isInputSourceFlutter=false on desktop (need "Input source 2")
flutter: [KEY_DIAG] [STAGE-1:RESULT] KeyEventResult.handled
```

**关键发现**:
- 所有键盘事件都在STAGE-2被阻止
- 输入源为 "Input source 1" (OS级别rdev键盘抓取模式)
- 在桌面平台上,当 `isInputSourceFlutter=false` 时,所有键盘事件都会被阻止
- STAGE-3、STAGE-4、STAGE-5 从未被执行

## 根本原因

### 输入源配置

RustDesk 支持两种键盘输入源模式 (`src/keyboard.rs:1146-1154`):

1. **Input source 1** (rdev模式):
   - 使用OS级别的键盘事件抓取
   - 通过 rdev 库直接监听系统键盘事件
   - 默认配置: `CONFIG_INPUT_SOURCE_DEFAULT = CONFIG_INPUT_SOURCE_1`

2. **Input source 2** (Flutter模式):
   - 使用Flutter的键盘事件系统
   - 通过Flutter框架处理键盘事件
   - 需要 `isInputSourceFlutter=true`

### 阻止逻辑

在 `flutter/lib/models/input_model.dart:555-579` 中:

```dart
KeyEventResult handleKeyEvent(KeyEvent e) {
  final actualInputSource = bind.mainGetInputSource();
  final platform = isDesktop ? 'desktop' : (isWeb ? 'web' : 'mobile');

  if (!isInputSourceFlutter) {
    if (isDesktop) {
      // ← 这里阻止了所有桌面平台的键盘事件
      debugPrint('[KEY_DIAG] [STAGE-2:BLOCKED] Blocked by isInputSourceFlutter=false on desktop');
      return KeyEventResult.handled;
    }
  }
  // ... 继续处理
}
```

在桌面平台上,如果输入源不是"Input source 2",则:
- 所有键盘事件在STAGE-2被立即阻止
- 返回 `KeyEventResult.handled` 防止事件继续传播
- 不会调用FFI桥接发送到远程系统

### 设备管理窗口的特殊性

普通远程桌面连接窗口和设备管理窗口使用不同的初始化路径:

- **普通连接**: 通过 `RemotePage` 创建,输入源可能在连接时正确设置
- **设备管理窗口**: 通过 `runDeviceManagementScreen()` 初始化,没有自动设置输入源

因此,设备管理窗口中的远程连接继承了默认的 "Input source 1" 配置,导致键盘输入失败。

## 解决方案

### 实现方式

在设备管理窗口启动时,自动将输入源设置为 "Input source 2" (Flutter模式)。

**修改文件**: `flutter/lib/main.dart:329-337`

```dart
void runDeviceManagementScreen() async {
  await initEnv(kAppTypeMain);

  // Set input source to "Input source 2" (Flutter keyboard mode) for device management
  // This ensures keyboard events are properly processed through Flutter's event system
  debugPrint('[DEVICE_MGMT] Setting input source to "Input source 2" for Flutter keyboard mode');
  await bind.mainSetLocalOption(key: 'input-source', value: 'Input source 2');
  final currentInputSource = bind.mainGetInputSource();
  debugPrint('[DEVICE_MGMT] Input source set to: "$currentInputSource"');

  // Build app with Provider for DeviceListModel
  final botToastBuilder = BotToastInit();
  runApp(RefreshWrapper(
    builder: (context) => ChangeNotifierProvider(
      create: (_) => DeviceListModel(),
      // ...
```

### 技术细节

1. **使用 `mainSetLocalOption` 而不是 `setInputSource`**:
   - `mainSetLocalOption` 直接设置本地配置选项,不需要会话ID
   - 配置键: `'input-source'`
   - 配置值: `'Input source 2'`

2. **调用时机**:
   - 在 `initEnv()` 之后
   - 在 `runApp()` 之前
   - 确保在创建任何远程连接之前配置生效

3. **日志确认**:
   - 启动时输出设置日志
   - 读取并输出当前输入源确认设置成功

### 验证方法

修复后的诊断日志应显示:

```
flutter: [DEVICE_MGMT] Setting input source to "Input source 2" for Flutter keyboard mode
flutter: [DEVICE_MGMT] Input source set to: "Input source 2"
```

建立远程连接并输入键盘后,应该看到完整的5个阶段:

```
flutter: [KEY_DIAG] [STAGE-1:UI_EVENT] type=KeyDownEvent, char="t", logical=T, physical=0x00070017, hasFocus=true
flutter: [KEY_DIAG] [STAGE-2:INPUT_MODEL] char="t", viewOnly=false, viewCamera=false
flutter: [KEY_DIAG] [STAGE-2:INPUT_SOURCE] actualValue="Input source 2", isInputSourceFlutter=true, platform=desktop
flutter: [KEY_DIAG] [STAGE-3:ROUTE] Routing to newKeyboardMode (map mode)
flutter: [KEY_DIAG] [STAGE-4:PREPARE_FFI] char="t", usbHid=0x0017, lockModes=0, down=true
flutter: [KEY_DIAG] [STAGE-5:FFI_CALLED] Sent to remote via FFI bridge
```

## 相关文件

### 修改的文件

1. **`flutter/lib/main.dart`** (核心修复)
   - 行 332-337: 添加输入源配置代码

2. **`flutter/lib/common/widgets/remote_input.dart`** (诊断日志)
   - 行 ~340: 添加 STAGE-1 诊断日志

3. **`flutter/lib/models/input_model.dart`** (诊断日志)
   - 行 555-579: 增强 STAGE-2 诊断日志
   - 添加 STAGE-3、STAGE-4、STAGE-5 诊断日志

### 参考的文件

1. **`src/keyboard.rs`**
   - 行 1146-1154: 输入源常量定义
   - 行 1165-1200: 输入源初始化和设置逻辑

2. **`flutter/lib/common.dart`**
   - 行 3342: `isInputSourceFlutter` getter定义

3. **`flutter/lib/models/state_model.dart`**
   - 行 119-129: 输入源getter和setter方法

4. **`flutter/lib/generated_bridge.dart`**
   - 行 757-760: `mainSetLocalOption` FFI接口定义
   - 行 772-775: `mainSetInputSource` FFI接口定义

## 测试

### 测试步骤

1. **启动设备管理窗口**:
   ```bash
   ./flutter/build/windows/x64/runner/Release/rustdesk.exe --devices
   ```

2. **确认输入源设置**:
   检查启动日志中是否包含:
   ```
   flutter: [DEVICE_MGMT] Input source set to: "Input source 2"
   ```

3. **建立远程连接**:
   - 双击设备列表中的设备
   - 等待远程桌面显示

4. **测试键盘输入**:
   - 在远程桌面区域点击以获取焦点
   - 输入测试文字 (例如: "test123")
   - 确认文字出现在远程系统中

5. **检查诊断日志**:
   - 查看所有5个阶段是否都出现在日志中
   - 确认没有STAGE-2阻止消息

### 预期结果

- 输入源成功设置为 "Input source 2"
- 键盘事件通过所有5个处理阶段
- 文字成功传输到远程系统
- 远程桌面正常显示用户输入

## 构建说明

```bash
# 构建Flutter应用
python build.py --flutter --skip-cargo

# 运行设备管理窗口(带诊断日志)
./flutter/build/windows/x64/runner/Release/rustdesk.exe --devices 2>&1 | tee keyboard_test.log
```

## 影响范围

### 影响的功能

- ✅ 设备管理窗口的键盘输入
- ✅ 从设备列表连接的远程桌面键盘输入

### 不影响的功能

- ✅ 普通远程桌面连接(通过连接ID)
- ✅ 主窗口的其他功能
- ✅ 鼠标输入和其他输入设备

### 兼容性

- **平台**: Windows, Linux, macOS (所有桌面平台)
- **Flutter版本**: 当前版本及后续版本
- **RustDesk版本**: 1.4.3-jlc16 及后续版本

## 总结

**问题**: 设备管理窗口中键盘输入无法传递到远程系统

**原因**: 默认输入源为 "Input source 1" (rdev模式),导致桌面平台上键盘事件在处理链路的STAGE-2被阻止

**解决**: 在设备管理窗口启动时自动设置输入源为 "Input source 2" (Flutter模式)

**效果**: 键盘事件完整通过5个处理阶段,成功传输到远程系统

## 后续建议

1. **考虑统一配置**: 评估是否应该在所有远程桌面场景中默认使用 "Input source 2"

2. **用户可配置**: 考虑在设置界面添加输入源选项,让用户可以选择偏好的输入模式

3. **自动检测**: 实现输入源失败时的自动降级或切换机制

4. **移除诊断日志**: 在正式版本中可以移除详细的诊断日志,保留关键的错误日志

5. **文档更新**: 在用户手册中说明两种输入源模式的区别和使用场景
