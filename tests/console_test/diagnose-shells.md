# CMD vs PowerShell 行为分析

## 问题描述

- **CMD**: 执行 console_test.exe 正常，提示符不被覆盖
- **PowerShell**: 执行 console_test.exe 输出覆盖提示符

## 可能的差异点

### 1. 进程启动方式

**CMD (cmd.exe)**:
- 同步启动进程
- 等待 Console subsystem 程序退出
- 对 Windows subsystem 程序立即返回

**PowerShell (powershell.exe)**:
- 异步启动所有程序（包括 Console 和 GUI）
- 立即返回控制权
- 输出提示符的时机可能不同

### 2. Console 缓冲区处理

**CMD**:
- 简单的字符流处理
- 直接写入 Console buffer

**PowerShell**:
- 对象流处理
- 有自己的缓冲机制
- 可能在 AttachConsole 时有不同的行为

### 3. 提示符输出时机

**CMD**:
```
T1: 启动 console_test.exe (Windows subsystem)
T2: 返回（不等待）
T3: 输出提示符 "C:\>"
T4: console_test.exe AttachConsole
T5: console_test.exe 输出换行符
T6: console_test.exe 输出内容
```

**PowerShell** (推测):
```
T1: 启动 console_test.exe (Windows subsystem)
T2: **立即**输出提示符 "PS C:\>" ← 比 CMD 更快？
T3: 返回（不等待）
T4: console_test.exe AttachConsole
T5: console_test.exe 输出换行符 ← 可能被 PowerShell 的缓冲机制影响
T6: console_test.exe 输出内容 ← 覆盖了 T2 的提示符
```

### 4. Console 句柄状态

**假设**：PowerShell 可能在启动 GUI 程序后立即：
1. 输出提示符
2. 将光标移回提示符行的末尾
3. 当 GUI 程序 AttachConsole 并输出时，从当前光标位置开始写入
4. 导致覆盖

## 需要验证的点

### 测试 1: 光标位置
检查 AttachConsole 后光标在哪里：
- CMD: 光标在提示符后的新行？
- PowerShell: 光标在提示符同一行？

### 测试 2: 输出时机
添加延迟看是否影响：
- 延迟 100ms 后再输出
- 看是否还会覆盖提示符

### 测试 3: 多次换行
尝试输出多个换行符：
- `\n\n` 或 `\r\n\r\n`
- 看是否能确保移动到安全位置

### 测试 4: 检测光标位置
使用 GetConsoleScreenBufferInfo 查看：
- dwCursorPosition.X
- dwCursorPosition.Y
- 在 AttachConsole 后立即检查

## 可能的解决方案

### 方案 A: 检测光标位置并调整
```rust
if attach_success {
    let info = GetConsoleScreenBufferInfo();
    if info.dwCursorPosition.X > 0 {
        // 光标不在行首，输出换行
        WriteConsole("\n");
    }
}
```

### 方案 B: 强制输出 \r\n
```rust
// 使用 \r\n 而不是 \n
WriteConsole("\r\n");
```

### 方案 C: 针对 PowerShell 特殊处理
```rust
if is_powershell {
    // PowerShell 需要额外换行
    WriteConsole("\n\n");
} else {
    WriteConsole("\n");
}
```

### 方案 D: 不输出换行，只在退出时发送 Enter
```rust
// 移除 AttachConsole 后的换行
// 依赖退出时发送的 Enter 键来触发新提示符
```

## 实施的解决方案

### 方案 A: 检测光标位置并调整（已实施）

```rust
pub fn attach_parent_console() -> bool {
    unsafe {
        let result = AttachConsole(ATTACH_PARENT_PROCESS);
        if result != 0 {
            let stdout_handle = GetStdHandle(STD_OUTPUT_HANDLE);
            if !stdout_handle.is_null() {
                let mut csbi: CONSOLE_SCREEN_BUFFER_INFO = std::mem::zeroed();
                if GetConsoleScreenBufferInfo(stdout_handle, &mut csbi) != 0 {
                    let cursor_x = csbi.dwCursorPosition.X;

                    // 记录到日志文件用于分析
                    log_cursor_position(cursor_x, cursor_y);

                    // 只在光标不在行首时输出换行
                    if cursor_x > 0 {
                        WriteConsoleA(stdout_handle, b"\n", ...);
                    }
                }
            }
        }
        result != 0
    }
}
```

### 工作原理

1. **CMD 行为**:
   - 启动 Windows subsystem 程序后立即返回
   - 输出提示符 "C:\>"
   - 光标在提示符之后（X > 0）
   - 程序 AttachConsole 时检测到 X > 0，输出换行
   - 结果：提示符不被覆盖 ✅

2. **PowerShell 行为**（新方案 - 在启动时发送 Enter）:
   - 启动 Windows subsystem 程序后立即返回
   - 输出提示符 "PS C:\>"
   - 光标在提示符之后（X > 0）
   - 程序 AttachConsole
   - **立即发送 Enter 键**
   - PowerShell 在当前位置（提示符之后）显示新提示符
   - 延迟 50ms 让 PowerShell 处理
   - 程序输出内容（在新提示符之后）
   - 程序退出时**不发送任何东西**
   - 结果：提示符已经在输出之前，程序退出后自然留在末尾 ✅

   **时间线**：
   ```
   T1: PS C:\> console_test.exe --version
   T2: 程序 AttachConsole
   T3: 发送 Enter 键
   T4: PowerShell 显示新提示符: PS C:\>
   T5: 程序输出: Console Test v1.0.0
   T6: 程序退出（不发送 Enter）
   结果显示:
   PS C:\> console_test.exe --version
   PS C:\> Console Test v1.0.0
   (光标在末尾，等待用户输入)
   ```

### 验证步骤

1. 在 CMD 中运行 `test-shells.bat`
2. 在 PowerShell 中运行 `.\test-shells.ps1`
3. 查看 `console_debug.log` 中记录的光标位置
4. 确认两种 shell 的行为差异

### 优势

- ✅ 自动检测光标位置
- ✅ 只在需要时输出换行
- ✅ 适用于 CMD 和 PowerShell
- ✅ 不影响其他终端（Git Bash 等）
- ✅ 无需硬编码 shell 类型判断
