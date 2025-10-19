# Terminal Output Module

一个独立的 Rust 模块，用于解决 Windows GUI 应用程序在不同终端（PowerShell、CMD、Git Bash 等）中的 CLI 输出问题。

## 问题背景

Windows GUI 应用程序（使用 `windows_subsystem = "windows"`）在需要提供 CLI 功能时面临以下挑战：

1. **PowerShell**: 输出后提示符位置不正确，覆盖在输出内容上
2. **CMD**: 输出后不自动显示新提示符
3. **Git Bash**: 工作正常，无需特殊处理

## 解决方案

`terminal_output` 模块提供了一个统一的 API，自动检测终端类型并应用相应的修复策略：

- **PowerShell**: 使用"prompt pushing"策略修复提示符位置
- **CMD**: 程序结束时发送 Enter 键触发新提示符
- **Git Bash**: 无需特殊处理

## 使用方法

### 1. 添加模块到项目

将 `terminal_output.rs` 复制到你的项目的 `src/` 目录。

### 2. 更新 Cargo.toml

确保包含必要的 winapi features：

```toml
[target.'cfg(windows)'.dependencies]
winapi = { version = "0.3", features = [
    "wincon", "winbase", "processenv", "handleapi", "winuser",
    "consoleapi", "psapi", "processthreadsapi", "wincontypes",
    "fileapi", "libloaderapi"
] }
```

### 3. 在代码中使用

```rust
mod terminal_output;

fn main() {
    // 1. 初始化终端输出处理
    terminal_output::init();

    // 2. 使用 terminal_output::println() 代替 println!()
    terminal_output::println("Hello, World!");
    terminal_output::println("Line 2");
    terminal_output::println("Line 3");

    // 3. 程序结束前清理
    terminal_output::cleanup();
}
```

## API 参考

### `terminal_output::init() -> bool`

初始化终端输出处理。必须在任何输出之前调用。

**返回值**: `true` 如果成功连接到父终端，`false` 否则

**示例**:
```rust
if !terminal_output::init() {
    eprintln!("Failed to attach to parent console");
}
```

### `terminal_output::println(text: &str)`

打印一行文本并换行。自动处理不同终端的兼容性问题。

**参数**:
- `text`: 要打印的文本

**示例**:
```rust
terminal_output::println("Console Test v1.0.0");
terminal_output::println(&format!("User: {}", username));
```

### `terminal_output::print(text: &str)`

打印文本但不换行。

**参数**:
- `text`: 要打印的文本

**注意**: 当前实现中，此函数存在但未在主代码中使用。

### `terminal_output::cleanup()`

清理终端状态。应在程序结束前调用。

**示例**:
```rust
terminal_output::cleanup();
std::process::exit(0);
```

## 工作原理

### 终端检测

模块在 `init()` 时检测父进程名称：

- `powershell.exe` → PowerShell 模式
- `cmd.exe` → CMD 模式
- `bash.exe` / `sh.exe` → Git Bash 模式
- 其他 → 默认模式

### PowerShell Prompt Pushing 策略

对于 PowerShell，每行输出执行以下步骤：

1. 获取当前光标位置（Y坐标）
2. 发送 Enter 键，将提示符推到下一行
3. 等待 10ms 让提示符移动
4. 将光标移回原位置
5. 清除该行
6. 输出实际内容

这确保了输出内容不会与提示符重叠。

### CMD Enter 键策略

对于 CMD，在 `cleanup()` 时发送一个 Enter 键事件到控制台输入缓冲区，触发新提示符的显示。

### 重定向检测

模块会检测 stdout 是否被重定向（管道或文件）：

- 如果重定向：使用标准 `println!()` 输出
- 如果是控制台：应用特殊处理策略

这确保了脚本中使用管道和重定向时能正常工作：

```powershell
# PowerShell 脚本中推荐使用
$output = .\your_app.exe --version 2>&1 | Out-String
```

## 限制和注意事项

1. **PowerShell 脚本直接调用**:
   - 在 PowerShell 脚本中直接调用（无重定向）可能会有显示问题
   - 推荐在脚本中使用管道 `|` 或重定向 `>` 来捕获输出

2. **性能**:
   - PowerShell 模式下每行有 10ms 延迟
   - 对于大量输出可能会有轻微性能影响

3. **编码**:
   - 目前只处理 UTF-8 文本
   - Windows 控制台默认使用 UTF-8 应该不会有问题

## 完整示例

参见 `src/main.rs` 中的完整实现示例。

```rust
#![cfg_attr(
    all(
        not(debug_assertions),
        target_os = "windows",
        not(feature = "cli")
    ),
    windows_subsystem = "windows"
)]

mod terminal_output;

fn main() {
    let args: Vec<String> = std::env::args().collect();

    if args.len() > 1 && args[1] == "--version" {
        terminal_output::init();
        terminal_output::println("MyApp v1.0.0");
        terminal_output::cleanup();
    } else {
        // GUI mode
        show_window();
    }
}
```

## 测试

测试不同终端：

```bash
# Git Bash
./target/release/console_test.exe --version

# CMD
target\release\console_test.exe --version

# PowerShell
.\target\release\console_test.exe --version

# PowerShell with pipe (recommended in scripts)
.\target\release\console_test.exe --version | Out-String
```

## 许可证

This module is part of the console_test project.
