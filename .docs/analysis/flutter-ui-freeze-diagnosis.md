# Flutter 界面不响应诊断指南

## 目录
- [常见问题类型](#常见问题类型)
- [WPA 定位分析步骤](#wpa-定位分析步骤)
- [具体案例分析](#具体案例分析)
- [诊断检查清单](#诊断检查清单)
- [修复方案](#修复方案)

---

## 常见问题类型

### 1. UI Thread 阻塞（最常见，占 70%）

**症状：**
- 点击按钮无反应
- 动画卡住不动
- 滚动无法响应
- 文本输入延迟

**原因：**

#### A. 同步执行耗时操作
```dart
// ❌ 错误示例：在 UI 线程读文件
onPressed() {
    setState(() {
        // 阻塞 UI Thread 100-1000ms
        String data = File('large.json').readAsStringSync();
        processData(data);
    });
}
```

#### B. 复杂的计算
```dart
// ❌ 错误示例：复杂计算
Widget build(BuildContext context) {
    // 每次重建都计算，耗时 50-200ms
    List<Item> filtered = hugeList.where((item) {
        return complexFilter(item);  // 复杂过滤逻辑
    }).toList();

    return ListView(children: filtered.map(...).toList());
}
```

#### C. 过度重建
```dart
// ❌ 错误示例：整个树重建
class MyApp extends StatefulWidget {
    @override
    Widget build(BuildContext context) {
        return MaterialApp(
            home: Scaffold(
                body: HugeWidgetTree(),  // 数千个 Widget
            ),
        );
    }
}

// 每次 setState 都重建整个树
setState(() { counter++; });
```

#### D. 同步网络请求
```dart
// ❌ 错误示例：同步 HTTP
onPressed() {
    // 阻塞 UI Thread 直到网络响应（可能几秒）
    var response = http.get('...').wait();
}
```

**WPA 特征：**
```
CPU Usage (Sampled) → UI Thread:

dart::DartEntry::InvokeFunction  [2000ms]  ← 异常长！
  └─ [Dart] _MyWidgetState.build
     └─ [Dart] File.readAsStringSync      ← 找到元凶
        └─ kernel32.dll!ReadFile
           └─ ntdll.dll!NtReadFile
```

---

### 2. Platform Thread 阻塞（占 20%）

**症状：**
- 窗口无法拖动
- 无法最小化/最大化/关闭窗口
- 右键菜单无反应
- 全屏切换卡住（您的问题可能是这个）

**原因：**

#### A. Platform Channel 同步调用耗时
```dart
// Dart 端
final result = await platform.invokeMethod('slowOperation');

// 原生端（C++）
// ❌ 错误：在主线程执行耗时操作
void HandleMethodCall(method_call, result) {
    if (method_call.method == "slowOperation") {
        // 阻塞主线程 5 秒
        Sleep(5000);
        result->Success(...);
    }
}
```

#### B. Windows API 调用慢
```cpp
// ❌ 示例：SetWindowPos 可能很慢
SetWindowPos(hwnd, HWND_TOP, 0, 0, 1920, 1080, ...);
// 在某些情况下（DWM 繁忙、显卡驱动问题）可能耗时数秒
```

#### C. 消息队列积压
```cpp
// 消息循环
while (GetMessage(&msg, NULL, 0, 0)) {
    // 如果某个消息处理很慢，后续消息都会延迟
    DispatchMessage(&msg);  // 可能在这里卡很久
}
```

**WPA 特征：**
```
CPU Usage (Sampled) → Platform Thread (主线程):

user32.dll!SetWindowPos  [8000ms]  ← 您的全屏卡顿！
  └─ dwmapi.dll!DwmFlush
     └─ ntdll.dll!NtWaitForSingleObject  ← 在等待 DWM
```

---

### 3. 死锁（占 5%）

**症状：**
- 界面完全冻结
- 强制关闭才能退出
- CPU 使用率低（因为在等待）

**原因：**

#### A. 互斥锁死锁
```dart
// ❌ 错误示例：经典死锁
// Thread A:
lock1.lock();
lock2.lock();  // 等待 Thread B 释放

// Thread B:
lock2.lock();
lock1.lock();  // 等待 Thread A 释放
```

#### B. Platform Channel 死锁
```dart
// Dart 端
final result = await platform.invokeMethod('getData');

// 原生端试图调用 Dart
// ❌ 错误：循环依赖
FlutterMethodChannel::InvokeMethod("callback", ...);
// 但 Dart 端正在等待这个方法返回
```

**WPA 特征：**
```
CPU Usage (Precise) → Thread State:

UI Thread:       ░░░░░░░░░░ (Waiting)
  └─ Waiting on: CriticalSection 0x12345678

Platform Thread: ░░░░░░░░░░ (Waiting)
  └─ Waiting on: CriticalSection 0x87654321

右键 → View Blocking Call Stack
→ 发现互相等待
```

---

### 4. 无限循环（占 3%）

**症状：**
- CPU 使用率 100%
- 界面卡死
- 风扇狂转

**原因：**

```dart
// ❌ 错误示例
Widget build(BuildContext context) {
    // 触发无限重建
    setState(() {});  // 导致 build 被再次调用

    return Container();
}

// 或
void processData() {
    while (true) {  // 忘记退出条件
        // ...
    }
}
```

**WPA 特征：**
```
CPU Usage (Sampled):

UI Thread CPU: 100%

调用栈：大量采样在同一个函数
dart::DartEntry::InvokeFunction  [Count: 1000+]
  └─ [Dart] _MyWidgetState.build  [Count: 1000+]
     └─ [Dart] setState            ← 循环调用
```

---

### 5. GPU 饥饿（占 2%）

**症状：**
- 输入事件正常响应
- 但屏幕显示不更新
- 或更新非常慢

**原因：**

```dart
// ❌ 复杂的绘制操作
CustomPaint(
    painter: ComplexPainter(),  // 绘制数千个图形
)

// 或大量的 Layer
Stack(
    children: List.generate(1000, (i) =>
        Opacity(  // 每个 Opacity 都创建一个 Layer
            opacity: 0.5,
            child: Container(...),
        ),
    ),
)
```

**WPA 特征：**
```
CPU Usage (Sampled) → Raster Thread:

flutter::Rasterizer::Draw  [100ms]  ← 光栅化太慢
  └─ SkCanvas::drawPath
     └─ GrContext::flush

GPU Utilization: 接近 100%
```

---

## WPA 定位分析步骤

### 快速诊断流程

```
1. 录制性能数据（捕获卡顿时刻）
   ↓
2. 识别哪个线程卡住
   ↓
3. 查看线程状态（Running vs Waiting）
   ↓
4. 分析调用栈
   ↓
5. 定位具体函数
   ↓
6. 确定修复方案
```

### 步骤 1: 录制卡顿时刻

**重要：** 必须在卡顿发生时录制

```powershell
# 启动录制
wpr -start CPU -start GPU

# 重现问题
# 例如：点击按钮导致卡顿

# 停止录制
wpr -stop ui_freeze.etl
```

**技巧：** 如果卡顿不频繁，可以长时间录制：
```powershell
# 循环缓冲，只保留最后 5 分钟
wpr -start CPU -start GPU -mode loop -numiterations 5
# ... 等待卡顿发生 ...
wpr -stop ui_freeze.etl  # 保存最近 5 分钟的数据
```

---

### 步骤 2: 打开 WPA 并加载符号

```powershell
wpa ui_freeze.etl
```

**加载符号（重要！）：**
1. **Trace** → **Configure Symbol Paths**
2. 添加：`SRV*C:\Symbols*https://msdl.microsoft.com/download/symbols`
3. **Trace** → **Load Symbols**（等待几分钟）

---

### 步骤 3: 识别卡顿时间段

**方法 A: 使用 UI Delays 视图（推荐）**

1. 拖拽 **UI Delays** 到主窗口
2. 筛选 **Process**: `rustdesk.exe`
3. 按 **Delay Duration** 降序排序
4. 找到异常长的延迟（>100ms）

```
结果示例：
Process       | Thread ID | Delay Duration | Delay Reason
rustdesk.exe  | 1234      | 8234 ms        | CPU_Scheduler
              ↑           ↑                ↑
            进程          线程              卡了 8 秒！
```

5. 记录 **Thread ID** 和时间戳

**方法 B: 手动在时间轴上定位**

1. 打开 **CPU Usage (Sampled)**
2. 在图表上找到明显的峰值或异常模式
3. 拖拽选择该时间段
4. 右键 → **Filter to Selection**

---

### 步骤 4: 分析线程状态

**使用 CPU Usage (Precise) 查看线程状态：**

1. 拖拽 **CPU Usage (Precise)** 到主窗口
2. 展开 `rustdesk.exe`
3. 找到卡顿的线程（通过 Thread ID）
4. 查看时间线上的状态颜色

**状态解读：**

| 状态 | 颜色 | 含义 | 可能原因 |
|------|------|------|---------|
| **Running** | 绿色 | 正在执行代码 | 计算密集型操作、无限循环 |
| **Ready** | 黄色 | 就绪但未调度 | CPU 资源不足、优先级低 |
| **Waiting** | 灰色 | 等待某个事件 | 锁、I/O、系统调用 |

**案例判断：**

```
案例 1: UI Thread 长时间 Running (绿色)
████████████████████  [5000ms Running]
→ 结论：正在执行耗时操作（计算/同步 I/O）
→ 下一步：查看调用栈，找到具体函数

案例 2: Platform Thread 长时间 Waiting (灰色)
░░░░░░░░░░░░░░░░░░░░  [8000ms Waiting]
→ 结论：在等待系统调用返回
→ 下一步：右键 → View Blocking Call Stack

案例 3: 多个线程都在 Waiting
UI Thread:       ░░░░░░░░ (Waiting on Lock A)
Platform Thread: ░░░░░░░░ (Waiting on Lock B)
→ 结论：可能死锁
→ 下一步：检查锁的依赖关系
```

---

### 步骤 5: 分析调用栈

**使用 CPU Usage (Sampled) 查看调用栈：**

1. 在 **CPU Usage (Sampled)** 视图中
2. 展开 `rustdesk.exe` → 找到卡顿的线程
3. 展开 **Stack** 列
4. 按 **Weight** 降序排序
5. 查看耗时最长的调用路径

**调用栈示例：**

```
示例 1: 同步文件读取（UI Thread 阻塞）

Weight: 2340 ms

rustdesk.exe!dart::DartEntry::InvokeFunction
  └─ [Dart] _HomePageState.build           ← Dart 代码
     └─ [Dart] File.readAsStringSync       ← 问题函数！
        └─ flutter_windows.dll!...
           └─ kernel32.dll!ReadFile        ← 系统调用
              └─ ntdll.dll!NtReadFile

→ 结论：在 build 方法中同步读文件
→ 修复：改为异步读取 + FutureBuilder
```

```
示例 2: SetWindowPos 慢（Platform Thread 阻塞）

Weight: 8234 ms

rustdesk.exe!FlutterDesktopView::HandleWindowMessage
  └─ user32.dll!SetWindowPos               ← 问题函数！
     └─ user32.dll!NtUserSetWindowPos
        └─ dwmapi.dll!DwmFlush              ← 等待 DWM
           └─ ntdll.dll!NtWaitForSingleObject

→ 结论：SetWindowPos 等待 DWM 响应
→ 修复：系统层问题，检查 DWM/显卡驱动
```

```
示例 3: 复杂布局计算（UI Thread 阻塞）

Weight: 1560 ms

flutter_windows.dll!flutter::Engine::OnAnimatorBeginFrame
  └─ [Dart] WidgetsBinding.drawFrame
     └─ [Dart] RenderObject.layout          ← 布局阶段
        └─ [Dart] RenderFlex.performLayout  ← 问题函数！
           └─ [大量嵌套的 layout 调用]

→ 结论：复杂的 Flex 布局计算
→ 修复：简化 Widget 树，减少嵌套
```

---

### 步骤 6: 使用 Wait Analysis（针对 Waiting 状态）

**如果线程处于 Waiting 状态：**

1. 在 **CPU Usage (Precise)** 中找到 Waiting 的线程
2. 右键该线程 → **View Blocking Call Stack**
3. 查看在等待什么

**等待原因分析：**

```
等待类型 1: 等待锁
ntdll.dll!NtWaitForSingleObject
  └─ Waiting on: Critical Section 0x12345678
  └─ Owned by: Thread 5678

→ 结论：被线程 5678 阻塞
→ 下一步：查看线程 5678 在做什么
```

```
等待类型 2: 等待 I/O
ntdll.dll!NtReadFile
  └─ File: C:\data\large.json
  └─ Bytes: 100MB

→ 结论：等待文件读取
→ 修复：异步读取或缓存
```

```
等待类型 3: 等待系统调用
user32.dll!SetWindowPos
  └─ dwmapi.dll!DwmFlush
     └─ Waiting for: DWM Composition

→ 结论：等待窗口合成器
→ 修复：系统层问题
```

---

### 步骤 7: 对比正常和异常情况

**如果卡顿不是每次都发生：**

1. **录制正常情况**（不卡顿的操作）
2. **录制异常情况**（卡顿的操作）
3. **对比两者的调用栈和耗时**

**对比方法：**

```powershell
# 分析脚本
$normal = Import-Csv "normal_case_export.csv"
$freeze = Import-Csv "freeze_case_export.csv"

# 找出只在卡顿时出现的函数
$freezeOnly = $freeze | Where-Object {
    $func = $_.Function
    -not ($normal | Where-Object { $_.Function -eq $func })
}

Write-Host "只在卡顿时出现的函数："
$freezeOnly | Format-Table Function, Weight -AutoSize
```

---

## 具体案例分析

### 案例 1: 点击按钮无反应

**症状：** 点击按钮后，等待 3 秒才有反应

**WPA 分析：**

1. **UI Delays** 显示：Thread 1234，Delay: 3240ms
2. **CPU Usage (Precise)** 显示：UI Thread Running（绿色）
3. **调用栈：**
   ```
   dart::DartEntry::InvokeFunction  [3240ms]
     └─ [Dart] _ButtonState._handleTap
        └─ [Dart] http.get(...).wait  ← 问题！
   ```

**结论：** 在按钮点击事件中同步等待网络请求

**修复：**
```dart
// ❌ 错误
onPressed() {
    var data = http.get('...').wait();  // 阻塞 UI
    setState(() { _data = data; });
}

// ✅ 正确
onPressed() async {
    setState(() { _loading = true; });
    var data = await http.get('...');   // 异步
    setState(() {
        _data = data;
        _loading = false;
    });
}
```

---

### 案例 2: 滚动列表卡顿

**症状：** 滚动 ListView 时，每次滑动都卡顿 100-200ms

**WPA 分析：**

1. **CPU Usage (Sampled)** 显示：UI Thread 频繁峰值
2. **调用栈（每次滚动）：**
   ```
   [Dart] ListView.build  [180ms]
     └─ [Dart] _buildItems
        └─ [Dart] _expensiveCalculation  ← 每个 item 10ms
   ```

**结论：** 列表项构建耗时，且未缓存

**修复：**
```dart
// ❌ 错误：每次滚动都重新计算
ListView.builder(
    itemBuilder: (context, index) {
        var data = expensiveCalculation(items[index]);
        return ListTile(title: Text(data));
    },
)

// ✅ 正确：预计算或缓存
class MyItem extends StatelessWidget {
    final String precomputedData;  // 预计算好的数据

    const MyItem(this.precomputedData);

    @override
    Widget build(BuildContext context) {
        return ListTile(title: Text(precomputedData));
    }
}
```

---

### 案例 3: 全屏切换卡顿 8 秒（您的问题）

**症状：** 按 F11 进入全屏，窗口卡住 8 秒

**WPA 分析：**

1. **UI Delays**: Platform Thread, Delay: 8234ms
2. **CPU Usage (Precise)**: Platform Thread Waiting（灰色）
3. **调用栈：**
   ```
   user32.dll!SetWindowPos  [8234ms]
     └─ dwmapi.dll!DwmFlush
        └─ ntdll.dll!NtWaitForSingleObject
   ```
4. **Generic Events**: 大量 `Microsoft-Windows-Dwm-Core` 事件

**结论：** SetWindowPos 等待 DWM 窗口合成

**可能原因：**
- DWM 繁忙（其他窗口占用）
- 显卡驱动问题
- 窗口特效过多

**修复方向：**
1. 检查是否有其他应用占用 GPU/DWM
2. 更新显卡驱动
3. 尝试禁用窗口特效
4. 考虑异步设置全屏（如果可能）

---

### 案例 4: 死锁导致完全冻结

**症状：** 窗口完全冻结，只能强制关闭

**WPA 分析：**

1. **CPU Usage (Precise)**:
   - UI Thread: Waiting
   - Platform Thread: Waiting
2. **Wait Analysis**:
   ```
   UI Thread:
     Waiting on: Lock 0xAABBCCDD
     Owned by: Platform Thread

   Platform Thread:
     Waiting on: Lock 0x11223344
     Owned by: UI Thread
   ```

**结论：** 经典死锁

**修复：**
- 重新设计锁的获取顺序
- 使用 try-lock 机制
- 减少跨线程锁的使用

---

## 诊断检查清单

### 快速诊断（5 分钟）

- [ ] **录制卡顿时刻的 ETL**
- [ ] **打开 UI Delays 视图**，找到最长延迟
- [ ] **记录 Thread ID** 和延迟时长
- [ ] **打开 CPU Usage (Precise)**，查看该线程状态
  - [ ] Running → 执行耗时操作
  - [ ] Waiting → 等待某个资源
- [ ] **打开 CPU Usage (Sampled)**，查看调用栈

### 深入分析（15 分钟）

- [ ] **加载符号**（Trace → Load Symbols）
- [ ] **展开调用栈**，找到具体函数
- [ ] **查看 Weight 列**，确认耗时
- [ ] **如果是 Waiting**：
  - [ ] 右键 → View Blocking Call Stack
  - [ ] 查看在等待什么
  - [ ] 检查是否死锁
- [ ] **如果是 Running**：
  - [ ] 查看是否在循环
  - [ ] 查看是否在同步 I/O
  - [ ] 查看是否在复杂计算
- [ ] **查看 Generic Events**（如果是系统调用慢）
- [ ] **查看 GPU Utilization**（如果是渲染问题）

### 对比分析（如果适用）

- [ ] **录制正常情况**
- [ ] **录制异常情况**
- [ ] **导出 CSV** 对比差异
- [ ] **找出只在卡顿时出现的函数**

---

## 修复方案

### 针对不同类型的修复

#### 1. UI Thread 阻塞 → 异步化

```dart
// 原则：UI Thread 不应执行 >5ms 的操作

// 文件读取
Future<String> loadData() async {
    return await File('data.json').readAsString();
}

// 复杂计算
Future<List<Item>> filterData() async {
    return await compute(heavyFilter, largeList);
}

// 网络请求
Future<Response> fetchData() async {
    return await http.get('...');
}
```

#### 2. Platform Thread 阻塞 → 原生层异步

```cpp
// ❌ 错误：阻塞主线程
void HandleMethodCall(method_call, result) {
    auto data = DoSlowOperation();  // 5 秒
    result->Success(data);
}

// ✅ 正确：异步执行
void HandleMethodCall(method_call, result) {
    std::thread([result]() {
        auto data = DoSlowOperation();
        // 回到主线程返回结果
        PostToMainThread([result, data]() {
            result->Success(data);
        });
    }).detach();
}
```

#### 3. 复杂布局 → 优化 Widget 树

```dart
// 使用 const
const Text('Hello')  // 不会重建

// 使用 RepaintBoundary 隔离
RepaintBoundary(
    child: ComplexWidget(),
)

// 拆分 Widget，减少重建范围
class MyButton extends StatelessWidget {
    // 只有这个 Widget 重建，不影响父级
}

// 避免过深嵌套
// ❌ 10 层嵌套
Container(child: Padding(child: Center(child: ...)))

// ✅ 使用组合 Widget
Card(child: ListTile(...))
```

#### 4. 死锁 → 锁顺序或无锁设计

```dart
// 统一锁顺序
void method1() {
    lock1.lock();
    lock2.lock();  // 始终先 lock1，再 lock2
    // ...
}

void method2() {
    lock1.lock();  // 保持相同顺序
    lock2.lock();
    // ...
}

// 或使用 try-lock
if (lock1.tryLock()) {
    if (lock2.tryLock()) {
        // 操作
        lock2.unlock();
    }
    lock1.unlock();
}
```

#### 5. GPU 饥饿 → 减少 Layer

```dart
// ❌ 避免过多 Opacity
Opacity(opacity: 0.5, child: ...)  // 创建 saveLayer

// ✅ 使用 Opacity widget 的 alwaysIncludeSemantics
AnimatedOpacity(...)  // 硬件加速

// ❌ 避免不必要的 ClipPath
ClipPath(clipper: ComplexClipper(), ...)

// ✅ 使用简单的 ClipRect
ClipRect(child: ...)
```

---

## 总结：定位流程图

```
界面不响应
    ↓
录制 ETL (wpr)
    ↓
打开 WPA
    ↓
查看 UI Delays
    ↓
找到卡顿的线程
    ↓
    ├─ Running (绿色) → 执行耗时操作
    │   ↓
    │   查看 CPU Usage (Sampled) 调用栈
    │   ↓
    │   ├─ 在 Dart 代码 → 优化应用逻辑
    │   ├─ 在文件 I/O → 改为异步
    │   ├─ 在网络请求 → 改为异步
    │   └─ 在 Layout/Paint → 优化 Widget 树
    │
    └─ Waiting (灰色) → 等待资源
        ↓
        View Blocking Call Stack
        ↓
        ├─ 等待锁 → 检查死锁，优化锁顺序
        ├─ 等待 I/O → 异步化
        └─ 等待系统调用 → 系统层问题
            ↓
            查看 Generic Events
            ↓
            ├─ DWM 事件多 → DWM 问题
            ├─ GPU 队列积压 → GPU 问题
            └─ 其他系统事件 → 相应处理
```

---

## 推荐工具组合

**诊断工具：**
1. **WPA** - 系统层分析（本文重点）
2. **Flutter DevTools** - Dart 层分析
3. **Process Monitor** - 文件/注册表 I/O 分析
4. **Process Explorer** - 线程状态实时监控

**最佳实践：同时使用多个工具**
- WPA 看系统层（Windows API、线程状态）
- DevTools 看应用层（Dart 代码、Widget 树）
- 对比两边时间线，找出瓶颈在哪一层

---

## 参考资源

- **Flutter 性能最佳实践**: https://docs.flutter.dev/perf/best-practices
- **WPA 官方文档**: https://docs.microsoft.com/en-us/windows-hardware/test/wpt/
- **项目内其他文档**:
  - `scripts/README-wpa-analysis.md`
  - `.docs/analysis/wpa-flutter-thread-analysis.md`
  - `.docs/analysis/flutter-rendering-mechanism.md`
