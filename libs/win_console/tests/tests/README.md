# Console Test Scripts

测试脚本用于验证 `console` 模块在不同终端环境下的行为。

## 测试脚本

### PowerShell
```powershell
cd tests
.\test-powershell.ps1
```

### CMD
```cmd
cd tests
test-cmd.bat
```

### Git Bash
```bash
cd tests
./test-bash.sh
```

## 测试内容

每个测试脚本都会验证以下功能：

1. **--version**: 单行输出测试
2. **--help**: 多行输出测试
3. **--test**: 复杂多行输出测试
4. **输出捕获**: 管道/重定向测试

## 预期结果

### PowerShell
- ✅ 输出正常显示
- ✅ 提示符自动返回到正确位置
- ✅ 管道捕获正常工作

### CMD
- ✅ 输出正常显示
- ✅ 程序退出后自动显示新提示符
- ✅ 重定向正常工作

### Git Bash
- ✅ 输出正常显示
- ✅ 提示符自动返回（无需特殊处理）
- ✅ 管道捕获正常工作

## 快速测试

在项目根目录直接运行：

```bash
# Git Bash 快速测试
./target/release/console_test.exe --version

# PowerShell 快速测试
.\target\release\console_test.exe --version

# CMD 快速测试
target\release\console_test.exe --version
```
