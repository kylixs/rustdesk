# Console Test

一个用于测试 Windows GUI 应用在不同终端（PowerShell、CMD、Git Bash）中 CLI 输出的示例程序。

## 项目结构

```
console_test/
├── src/
│   ├── main.rs          # 主程序 (87 行)
│   ├── console.rs       # 跨终端控制台输出模块
│   └── gui.rs           # GUI 窗口模块
├── tests/
│   ├── README.md        # 测试说明
│   ├── test-powershell.ps1
│   ├── test-cmd.bat
│   └── test-bash.sh
├── Cargo.toml
└── README.md
```

## 核心模块：Console

独立的控制台输出模块，自动处理不同终端的兼容性问题。

### 特性

- ✅ **自动检测终端**：PowerShell、CMD、Git Bash
- ✅ **自动修复**：Prompt pushing (PowerShell)、Enter 键 (CMD)
- ✅ **自动清理**：程序退出时自动处理，无需手动调用
- ✅ **支持重定向**：管道和文件重定向自动检测
- ✅ **零配置**：只需调用 `init()`

### 使用方法

```rust
mod console;
use console::println;

fn main() {
    console::init();           // 初始化（自动注册退出处理）

    println("Hello, World!");  // 直接使用
    println("Line 2");

    // 无需 cleanup() - 自动处理！
}
```

## 构建

```bash
# 开发版本
cargo build

# 发布版本
cargo build --release
```

## 测试

### 快速测试
```bash
# Git Bash
./target/release/console_test.exe --version

# PowerShell
.\target\release\console_test.exe --version

# CMD
target\release\console_test.exe --version
```

### 完整测试
参见 [tests/README.md](tests/README.md)

```bash
cd tests

# PowerShell
.\test-powershell.ps1

# CMD
test-cmd.bat

# Git Bash
./test-bash.sh
```

## 命令行参数

- `--version` - 显示版本
- `--help` - 显示帮助
- `--test` - 运行测试（多行输出）
- `--gui` 或无参数 - 显示 GUI 窗口

## 技术细节

### PowerShell Prompt Pushing

1. 获取当前光标位置
2. 发送 Enter 键（推动提示符）
3. 等待 10ms
4. 移动光标回原位置
5. 清除该行
6. 输出内容

### 自动清理机制

使用 `libc::atexit()` 在程序初始化时注册清理函数，程序退出时自动发送 Enter 键（PowerShell 和 CMD）。
