# WPA 中分析 Flutter 渲染和事件处理堵塞

## 目录
- [Flutter 线程模型](#flutter-线程模型)
- [在 WPA 中识别 Flutter 线程](#在-wpa-中识别-flutter-线程)
- [分析渲染堵塞](#分析渲染堵塞)
- [分析事件处理堵塞](#分析事件处理堵塞)
- [实际案例分析](#实际案例分析)

---

## Flutter 线程模型

Flutter Windows 应用有以下关键线程：

### 1. Platform Thread (主线程)
- **职责**：Windows 消息循环、窗口事件、Platform Channels
- **堵塞后果**：窗口无响应（ANR），但不一定掉帧
- **在 WPA 中的标识**：通常是主线程（Thread ID 最小），调用栈包含 `WinMain`, `WindowProc`

### 2. UI Thread (Dart VM 线程)
- **职责**：
  - 执行 Dart 代码
  - Widget 树构建 (build)
  - 布局计算 (layout)
  - 绘制指令生成 (paint)
  - 生成 Layer Tree
- **堵塞后果**：帧率下降，UI 卡顿，**最常见的性能瓶颈**
- **在 WPA 中的标识**：调用栈包含 `dart::`, `Dart_Invoke`, `flutter::Engine::`

### 3. Raster Thread (GPU 线程)
- **职责**：
  - 接收 Layer Tree
  - 执行 Skia 光栅化
  - 提交 GPU 指令
  - Present 到屏幕
- **堵塞后果**：GPU 等待，Present 延迟，掉帧
- **在 WPA 中的标识**：调用栈包含 `flutter::Rasterizer::`, `SkCanvas::`, `GrContext::`

### 4. IO Thread
- **职责**：图片解码、资源加载、异步 IO
- **堵塞后果**：资源加载慢，不直接影响渲染
- **在 WPA 中的标识**：调用栈包含 `flutter::IOManager::`, `SkCodec::`

---

## 在 WPA 中识别 Flutter 线程

### 步骤 1: 打开 CPU Usage (Sampled)

1. 从左侧 **Graph Explorer** 拖拽 **CPU Usage (Sampled)** 到主窗口
2. 在表格中找到 `rustdesk.exe` 进程
3. 展开 **Process** -> 展开 **Thread**

### 步骤 2: 添加有用的列

右键表头，添加以下列（如果没有）：
- **Thread ID**: 线程唯一标识
- **Stack**: 调用栈
- **Weight**: CPU 时间（毫秒）
- **% Weight**: CPU 时间百分比
- **Count**: 采样次数

### 步骤 3: 识别线程类型

展开每个线程，查看 **Stack** 列的顶层函数：

```
✓ 正确的识别方式：

Thread 1234 (主线程)
  └─ ntdll.dll!NtWaitForSingleObject
     └─ user32.dll!GetMessageW
        └─ FlutterDesktopView::HandleWindowMessage
           └─ WM_NCCALCSIZE / WM_WINDOWPOSCHANGING
  → 这是 Platform Thread，处理 Windows 消息

Thread 5678 (UI 线程)
  └─ dart::DartEntry::InvokeFunction
     └─ Dart_Invoke
        └─ flutter::Engine::OnAnimatorBeginFrame
           └─ [Dart] _WidgetsFlutterBinding.drawFrame
  → 这是 UI Thread，执行 Dart 代码和渲染管线

Thread 9012 (Raster 线程)
  └─ flutter::Rasterizer::Draw
     └─ SkCanvas::drawPicture
        └─ GrContext::flush
           └─ gl::SwapBuffers
  → 这是 Raster Thread，执行光栅化和 GPU 提交
```

### 步骤 4: 符号问题处理

如果看到 `?!?` 符号无法解析：

**A. Windows 系统符号：**
```powershell
# 配置符号路径
setx _NT_SYMBOL_PATH "SRV*C:\Symbols*https://msdl.microsoft.com/download/symbols"

# 在 WPA 中：Trace -> Configure Symbol Paths
# 添加：SRV*C:\Symbols*https://msdl.microsoft.com/download/symbols

# 加载符号：Trace -> Load Symbols
```

**B. Flutter 引擎符号：**
```powershell
# 复制 Flutter 引擎 PDB 文件
cp C:\flutter\bin\cache\artifacts\engine\windows-x64-profile\flutter_windows.dll.pdb `
   flutter\build\windows\x64\runner\Profile\
```

**C. Rust 代码符号：**
- 确保使用 Profile 或 Debug 构建
- PDB 文件应在 exe 同目录
- 在 Cargo.toml 中确保 `[profile.release]` 有 `debug = 1`

---

## 分析渲染堵塞

### 什么是渲染堵塞？

- **UI Thread 堵塞**：Widget 构建、布局、绘制耗时过长（>16ms = 60fps）
- **Raster Thread 堵塞**：GPU 光栅化、Present 耗时过长

### 检测方法

#### 方法 1: 使用 CPU Usage (Sampled)

1. **筛选时间段**：右键图表，选择卡顿发生的时间段，**Filter to Selection**

2. **查看 UI Thread CPU 使用**：
   - 找到调用栈包含 `dart::` 的线程
   - 查看 **Weight** 列：如果连续多个采样点在同一函数，说明该函数耗时长
   - 展开 **Stack**，查看是哪个 Dart 函数

3. **关键指标**：
   ```
   正常情况（60 fps）：
   - 每帧耗时：< 16.67 ms
   - UI Thread CPU：< 10 ms/frame
   - Raster Thread CPU：< 6 ms/frame

   卡顿情况：
   - 帧耗时：> 50 ms
   - UI Thread 持续在某个函数中（例如 100+ ms）
   ```

#### 方法 2: 使用 UI Delays 视图

1. 拖拽 **UI Delays** 到主窗口
2. 在 **Process** 列筛选 `rustdesk.exe`
3. 查看：
   - **Delay Duration**: 延迟时长（>100ms 视为严重）
   - **Delay Reason**: 延迟原因
     - `CPU_Scheduler`: CPU 调度延迟
     - `Waiting`: 等待某个资源
     - `CrossProcess`: 跨进程调用延迟

#### 方法 3: 使用 Thread State 视图

1. 拖拽 **CPU Usage (Precise)** 或 **Thread Lifetimes** 到主窗口
2. 找到 UI Thread 和 Raster Thread
3. 查看时间线上的线程状态：
   - **Running** (绿色): 正在执行
   - **Ready** (黄色): 就绪但未调度
   - **Waiting** (灰色): 等待某个事件

   ```
   卡顿模式识别：

   模式 1: UI Thread 长时间 Running
   ████████████████████ (100+ ms Running)
   → UI 计算密集型操作（layout、build）

   模式 2: UI Thread 长时间 Waiting
   ░░░░░░░░░░░░░░░░░░░░ (100+ ms Waiting)
   → 等待锁、等待平台调用返回

   模式 3: Raster Thread 长时间 Running
   GPU ████████████████ (50+ ms Running)
   → GPU 光栅化慢、复杂绘制
   ```

---

## 分析事件处理堵塞

### 什么是事件处理堵塞？

用户输入（点击、按键）到 UI 响应的延迟过长，通常由以下原因导致：
1. **Platform Thread 堵塞**：Windows 消息处理慢
2. **Platform Channel 调用慢**：Dart 调用原生代码耗时
3. **UI Thread 繁忙**：正在处理其他任务，无法及时响应事件

### 检测方法

#### 方法 1: 查找输入事件处理路径

在 **Generic Events** 视图中：

1. 拖拽 **Generic Events** 到主窗口
2. 筛选 **Provider Name**: `Microsoft-Windows-Win32k`
3. 筛选 **Task Name**:
   - `Input` - 输入事件
   - `MouseInput` - 鼠标事件
   - `KeyboardInput` - 键盘事件

4. 记录事件时间戳，然后在 **CPU Usage** 中查看对应时间的调用栈

#### 方法 2: 跟踪全屏切换事件

对于您的全屏卡顿问题，重点查找：

```
事件序列：
1. 用户按 F11 键
   → Generic Events: KeyboardInput (F11)
   → 时间戳 T0

2. Platform Thread 接收 WM_KEYDOWN
   → CPU Usage: user32.dll!DispatchMessageW
   → 时间戳 T0 + 1ms

3. Flutter Platform Channel 调用
   → CPU Usage: FlutterDesktopMessenger::Send
   → 时间戳 T0 + 5ms

4. Dart 代码处理
   → CPU Usage: dart::DartEntry::InvokeFunction
   → 时间戳 T0 + 10ms

5. 调用 window_manager 插件
   → CPU Usage: WindowManagerPlugin::SetFullscreen
   → 时间戳 T0 + 15ms

6. Windows API: SetWindowPos
   → CPU Usage: user32.dll!SetWindowPos
   → 时间戳 T0 + 20ms

7. DWM 窗口合成
   → Generic Events: Microsoft-Windows-Dwm-Core
   → 时间戳 T0 + 8000ms  ← 这里有问题！

8. 窗口重绘完成
   → 时间戳 T0 + 8100ms
```

**分析延迟发生在哪里**：
- T0 → T0+20ms: 正常（事件处理和 API 调用）
- T0+20ms → T0+8000ms: **异常延迟 8 秒** ← 重点分析这段

#### 方法 3: 使用 Wait Analysis

1. 在 **CPU Usage (Precise)** 视图中
2. 右键某个长时间 Waiting 的线程
3. 选择 **View Blocking Call Stack**
4. 查看是什么导致线程等待：
   - `NtWaitForSingleObject` - 等待对象
   - `Sleep` - 主动休眠
   - `CriticalSection` - 锁等待

---

## 实际案例分析

### 案例：全屏切换卡顿 8 秒

**症状**：
- 按 F11 进入全屏模式时，窗口卡住 8 秒
- 退出全屏正常

**WPA 分析步骤**：

#### 1. 定位问题时间段

在时间轴上找到卡顿发生的 8 秒区间：
- 方法 1: 对照 Flutter 日志时间戳
- 方法 2: 在 **Generic Events** 中搜索 `F11` 按键事件
- 方法 3: 在 **CPU Usage** 图表上找到明显的空白或峰值

#### 2. 分析 Platform Thread

在 **CPU Usage (Sampled)** 中：
```
展开 rustdesk.exe -> Platform Thread (主线程)

如果看到：
  user32.dll!SetWindowPos
    └─ [Time: 8.2 seconds, Weight: 8200 ms]

→ 说明 SetWindowPos 调用本身耗时 8 秒（Windows API 层面问题）
```

**可能原因**：
- DWM (Desktop Window Manager) 繁忙
- 其他窗口阻塞了窗口消息队列
- 显卡驱动问题

#### 3. 分析 DWM 活动

在 **Generic Events** 中：
```
筛选 Provider: Microsoft-Windows-Dwm-Core
筛选时间段：卡顿的 8 秒

查看：
- DwmRedirection 事件
- DwmComposition 事件
- DwmFlush 事件

如果有大量事件或长时间事件，说明 DWM 繁忙
```

#### 4. 检查 GPU 活动

在 **GPU Utilization** 中：
```
查看卡顿期间 GPU 使用率：
- 如果 GPU 接近 100%，可能是显卡驱动或硬件问题
- 如果 GPU 很低（<10%），说明 CPU 端阻塞
```

#### 5. 查看是否有锁争用

在 **CPU Usage (Precise)** -> **Thread State** 中：
```
Platform Thread 状态：

如果是 Waiting:
  → 右键 -> View Blocking Call Stack
  → 查看在等待什么

常见情况：
- 等待 Raster Thread 完成 Present
- 等待 DWM 确认窗口状态
- 等待其他进程（如杀毒软件）
```

---

## 总结：快速诊断检查清单

### 渲染堵塞检查清单

- [ ] **打开 CPU Usage (Sampled)**，找到 rustdesk.exe
- [ ] **识别 UI Thread**：调用栈包含 `dart::`, `Dart_Invoke`
- [ ] **识别 Raster Thread**：调用栈包含 `flutter::Rasterizer::`, `SkCanvas::`
- [ ] **查看 Weight 列**：单帧耗时 >16ms 表示掉帧
- [ ] **展开调用栈**：找到具体是哪个 Dart 函数或原生函数慢
- [ ] **打开 UI Delays**：查看是否有 >100ms 的延迟
- [ ] **对比 Flutter DevTools**：确认是 Dart 层还是原生层问题

### 事件处理堵塞检查清单

- [ ] **打开 Generic Events**，找到输入事件（KeyboardInput, MouseInput）
- [ ] **记录事件时间戳**
- [ ] **在 CPU Usage 中查看对应时间**的 Platform Thread 调用栈
- [ ] **查找 Platform Channel 调用**：`FlutterDesktopMessenger::Send`
- [ ] **跟踪到原生插件代码**：如 `WindowManagerPlugin::*`
- [ ] **查看 Windows API 调用**：`SetWindowPos`, `ShowWindow` 等
- [ ] **检查 DWM 事件**：是否有长时间的窗口合成
- [ ] **使用 Wait Analysis**：如果线程 Waiting，查看等待原因

### 符号问题检查清单

- [ ] **配置 Windows 符号服务器**：`_NT_SYMBOL_PATH`
- [ ] **加载符号**：WPA -> Trace -> Load Symbols
- [ ] **复制 Flutter 引擎 PDB**：`flutter_windows.dll.pdb`
- [ ] **确保 Rust PDB 存在**：与 rustdesk.exe 同目录
- [ ] **构建包含调试信息**：`debug = 1` in Cargo.toml

---

## 参考资源

- **Flutter 性能分析官方文档**: https://docs.flutter.dev/perf
- **WPA 官方文档**: https://docs.microsoft.com/en-us/windows-hardware/test/wpt/
- **Flutter 引擎架构**: https://github.com/flutter/flutter/wiki/The-Engine-architecture
- **项目内其他文档**:
  - `scripts/README-wpa-analysis.md` - WPA 基础使用
  - `scripts/README-devtools-analysis.md` - DevTools 分析

---

## 下一步

找到瓶颈后：
1. **如果是 UI Thread 慢**：优化 Dart 代码，减少 build/layout 计算
2. **如果是 Raster Thread 慢**：简化绘制，减少 layer 数量
3. **如果是 Platform Channel 慢**：优化原生插件代码
4. **如果是 Windows API 慢**：考虑异步调用或替代方案
5. **如果是 DWM 慢**：检查系统设置、显卡驱动、其他应用干扰
