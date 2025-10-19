# Console Test Program

这是一个用于**重现** Windows 控制台行为问题的测试程序，模拟 RustDesk 的 GUI/CLI 模式切换行为。

## ⚠️ 当前状态：问题重现版本

这个版本**不包含任何解决方案**，仅用于重现和验证问题。

## 问题描述

使用 `windows_subsystem = "windows"` 的 GUI 程序在处理 CLI 参数时：

1. ✅ GUI 双击运行 - 无控制台窗口闪现（符合预期）
2. ❌ CLI 执行后 - 终端不会自动返回提示符（需要手动按 Enter）

## 编译

```bash
cd tests/console_test
cargo build --release
```

编译后的可执行文件：`../../target/release/console_test.exe`

## 测试问题

### CLI 模式测试

```bash
# 从项目根目录
cd target/release

# 测试版本输出
./console_test.exe --version
# 问题：输出后不会自动返回提示符，需要手动按 Enter

# 测试帮助
./console_test.exe --help
# 问题：同上

# 测试详细输出
./console_test.exe --test
# 问题：同上
```

### 预期问题行为

```
C:\> console_test.exe --version
Console Test v1.0.0
                        ← 光标停在这里，需要手动按 Enter
C:\>                    ← 按 Enter 后才显示提示符
```

### GUI 模式测试

```bash
# 双击运行或：
./console_test.exe

# 或明确指定 GUI 模式：
./console_test.exe --gui

# 预期：正常显示窗口，无控制台闪现
```

## 技术细节

### 为什么会有这个问题？

1. **`windows_subsystem = "windows"`** - 程序编译为 GUI subsystem
2. **cmd.exe 的行为** - Shell 不等待 GUI subsystem 程序退出
3. **AttachConsole** - 程序可以附加到父console并输出内容
4. **BUT**: Shell 已经"返回"了，虽然进程还在运行

### 时间线

```
T0: 用户输入 "console_test --version"
T1: cmd.exe 启动 console_test.exe (Windows subsystem)
T2: cmd.exe 立即返回（不等待）
T3: console_test.exe AttachConsole成功
T4: console_test.exe 输出 "Console Test v1.0.0"
T5: console_test.exe 退出
T6: ❌ 终端不显示新提示符（需要用户按 Enter）
```

## 文件结构

```
tests/console_test/
├── src/
│   └── main.rs              - 单一可执行文件（重现问题）
├── Cargo.toml
└── README.md                - 本文件
```

## 代码关键部分

**windows_subsystem配置**:
```rust
#![cfg_attr(
    all(
        not(debug_assertions),
        target_os = "windows",
        not(feature = "cli")
    ),
    windows_subsystem = "windows"
)]
```

**CLI处理**:
```rust
if is_cli_mode {
    // 附加到父console
    windows_console::attach_parent_console();

    // 输出内容
    println!("Console Test v1.0.0");

    // 刷新输出
    std::io::stdout().flush().unwrap();
}
```

## 在不同终端中测试

### CMD (命令提示符)
```cmd
C:\> console_test.exe --version
Console Test v1.0.0
                        ← 需要按 Enter
C:\>
```

### PowerShell
```powershell
PS C:\> console_test.exe --version
Console Test v1.0.0
                        ← 需要按 Enter
PS C:\>
```

### Git Bash
```bash
$ console_test.exe --version
Console Test v1.0.0
                        ← 需要按 Enter
$
```

## 核心问题

**Windows 设计限制**：
- cmd.exe/PowerShell 是否等待进程，由 PE 文件头的 subsystem 字段决定
- Windows subsystem (2) = Shell 不等待
- Console subsystem (3) = Shell 等待
- 这个决定在程序启动**之前**就做出，无法运行时改变

**没有完美的单一 EXE 解决方案**（在当前设计下）

## 已尝试并撤销的方案

以下方案已被测试但存在问题，已撤销：

1. ❌ **发送 Enter 键** - Git Bash 会多输出空行
2. ❌ **.COM 包装程序** - 需要额外文件
3. ❌ **GUI启动CLI子进程** - console 提示符位置错乱
4. ❌ **AttachConsole + 换行符** - 仍然存在问题

## 下一步

这个测试程序现在处于**问题重现状态**，可以用于：

1. 验证问题确实存在
2. 在不同终端环境中测试
3. 作为后续解决方案的测试基准

需要找到一个真正有效的解决方案。
