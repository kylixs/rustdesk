# Testing Guide for RustDesk Portable Packer

## Quick Start

### 1. 编译项目

```powershell
cd libs\portable
cargo build --release
```

### 2. 运行快速测试（推荐）

```powershell
# 进入测试目录
cd tests

# 运行快速测试（约30秒）
.\quick-test.ps1
```

**示例输出：**
```
========================================
RustDesk Portable Packer Quick Test
========================================

► Step 1: Cleanup
  ✓ OK

► Step 2: Initial Extraction
  ✓ OK

► Step 3: Normal Startup (should be fast)
  ✓ OK

► Step 4: Verify Command
  ✓ OK

► Step 5: File Corruption & Auto-Repair
  Corrupted rustdesk.exe
  ✓ OK

► Step 6: Manual Repair Command
  ✓ OK

► Step 7: Dump Manifest
  ✓ OK

► Step 8: Running Process Detection
  Modified timestamp
  ✓ OK

========================================
✓ All Quick Tests Passed!
========================================
```

### 3. 运行完整测试套件（可选）

```powershell
# 进入测试目录（如果还未进入）
cd libs\portable\tests

# 运行所有14个测试用例（约2-3分钟）
.\test-portable.ps1
```

**示例输出：**
```
========================================
TEST: Test 1: Initial Extraction (Clean Install)
========================================
✓ PASSED in 1.234s

========================================
TEST: Test 2: Normal Startup (No Changes)
========================================
✓ PASSED in 0.456s

... (更多测试)

========================================
TEST SUMMARY
========================================

Name                                      Result Duration Error
----                                      ------ -------- -----
Test 1: Initial Extraction               PASS   1.234
Test 2: Normal Startup                   PASS   0.456
Test 3: Timestamp Mismatch (No Process)  PASS   1.123
...

Total Tests: 14
✓ Passed: 14
✗ Failed: 0

🎉 All tests passed!
```

## 测试用例概览

| 测试类型 | 测试数量 | 验证内容 |
|---------|---------|---------|
| 🚀 启动性能 | 2 | 首次解压、正常启动速度 |
| 🔄 版本管理 | 2 | Timestamp匹配、重新构建处理 |
| 📦 Manifest | 2 | 一致性检查、自动恢复 |
| 🔧 文件修复 | 2 | 自动恢复、手动修复 |
| 🛡️ 安全检查 | 4 | 进程检测、锁定保护 |
| 📋 命令验证 | 3 | --verify, --repair, --dump-manifest |
| ⚡ 性能优化 | 1 | 进程检查只执行一次 |

## 手动测试示例

### 示例 1: 测试基本功能

```powershell
# 1. 清理环境
$version = "1.4.3-jlc20"  # 使用实际版本
Remove-Item "C:\ProgramData\RustDesk\bin\$version" -Recurse -Force -ErrorAction SilentlyContinue

# 2. 首次运行
.\target\release\rustdesk-portable-packer.exe --version

# 3. 验证文件
dir "C:\ProgramData\RustDesk\bin\$version"
# 应该看到: rustdesk.exe, .rustdesk_manifest.bin, meta.toml 等

# 4. 验证完整性
.\target\release\rustdesk-portable-packer.exe --verify
# 预期输出: Status: OK ✓
```

### 示例 2: 测试进程冲突检测

```powershell
# 1. 确保环境干净
$version = "1.4.3-jlc20"
$extractDir = "C:\ProgramData\RustDesk\bin\$version"
.\target\release\rustdesk-portable-packer.exe --version

# 2. 模拟重新构建（修改timestamp）
$metaFile = Join-Path $extractDir "meta.toml"
(Get-Content $metaFile) -replace 'timestamp = \d+', 'timestamp = 9999999999' | Set-Content $metaFile

# 3. 启动一个进程
$process = Start-Process (Join-Path $extractDir "rustdesk.exe") -ArgumentList "--version" -PassThru

# 4. 尝试再次运行（应该失败并提示修复）
.\target\release\rustdesk-portable-packer.exe --version

# 预期输出:
# ERROR: Installation Requires Repair
# ...
# To repair: rustdesk-portable-packer.exe --repair

# 5. 清理
Stop-Process -Id $process.Id -Force
```

### 示例 3: 测试文件损坏恢复

```powershell
# 1. 正常运行一次
.\target\release\rustdesk-portable-packer.exe --version

# 2. 损坏一个文件
$version = "1.4.3-jlc20"
$exePath = "C:\ProgramData\RustDesk\bin\$version\rustdesk.exe"
Write-Host "Original size: $((Get-Item $exePath).Length) bytes"
[System.IO.File]::WriteAllBytes($exePath, [byte[]]::new(100))
Write-Host "Corrupted size: $((Get-Item $exePath).Length) bytes"

# 3. 再次运行（应该自动恢复）
.\target\release\rustdesk-portable-packer.exe --version

# 4. 验证恢复
Write-Host "Restored size: $((Get-Item $exePath).Length) bytes"
# 预期: > 1,000,000 bytes
```

### 示例 4: 测试 --repair 命令

```powershell
# 1. 创建各种问题
$version = "1.4.3-jlc20"
$extractDir = "C:\ProgramData\RustDesk\bin\$version"

# 损坏文件
$exePath = Join-Path $extractDir "rustdesk.exe"
[System.IO.File]::WriteAllBytes($exePath, [byte[]]::new(100))

# 删除 manifest
Remove-Item (Join-Path $extractDir ".rustdesk_manifest.bin") -Force

# 2. 使用 --repair 修复
.\target\release\rustdesk-portable-packer.exe --repair

# 预期输出:
# RustDesk Portable Repair
# ...
# ========================================
# Repair completed successfully!
# ========================================

# 3. 验证
.\target\release\rustdesk-portable-packer.exe --verify
# 预期: Status: OK ✓
```

## 性能测试

### 测试启动速度

```powershell
# 首次启动（解压）
Measure-Command {
    .\target\release\rustdesk-portable-packer.exe --version
}
# 预期: < 5秒

# 第二次启动（无变化）
Measure-Command {
    .\target\release\rustdesk-portable-packer.exe --version
}
# 预期: < 2秒
```

### 测试进程检测性能

```powershell
# 启用debug日志查看详细时间
$env:RUST_LOG = "debug"

.\target\release\rustdesk-portable-packer.exe --version 2>&1 | Select-String "Process check"

# 预期输出:
# Process check completed in 3.456ms, has_running: false

$env:RUST_LOG = $null
```

## 查看日志

```powershell
# 日志目录
$logDir = "C:\ProgramData\RustDesk\log\portable-packer"

# 查看最新日志
Get-ChildItem $logDir | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Get-Content -Tail 50

# 搜索错误
Get-ChildItem $logDir\*.log | Select-String "ERROR" | Select-Object -Last 10
```

## 故障排查

### 测试失败时的检查清单

1. **检查可执行文件是否存在**
   ```powershell
   Test-Path ".\target\release\rustdesk-portable-packer.exe"
   ```

2. **检查版本号**
   ```powershell
   .\target\release\rustdesk-portable-packer.exe --version
   ```

3. **清理所有进程**
   ```powershell
   Get-Process rustdesk -ErrorAction SilentlyContinue | Stop-Process -Force
   ```

4. **清理测试目录**
   ```powershell
   Remove-Item "C:\ProgramData\RustDesk\bin\*" -Recurse -Force
   ```

5. **重新编译**
   ```powershell
   cargo clean
   cargo build --release
   ```

6. **查看日志**
   ```powershell
   Get-Content "C:\ProgramData\RustDesk\log\portable-packer\portable-packer-*.log" -Tail 100
   ```

## 常见问题

### Q: 测试脚本报错 "execution policy"

**A:** 设置 PowerShell 执行策略
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Q: 无法写入 C:\ProgramData

**A:** 以管理员权限运行 PowerShell
```powershell
# 右键 PowerShell -> "以管理员身份运行"
```

### Q: rustdesk.exe 进程无法启动

**A:** 文件可能已损坏，使用 --repair 修复
```powershell
.\target\release\rustdesk-portable-packer.exe --repair
```

### Q: 测试一直失败

**A:** 完全清理后重新开始
```powershell
# 停止所有进程
Get-Process rustdesk* -ErrorAction SilentlyContinue | Stop-Process -Force

# 删除所有文件
Remove-Item "C:\ProgramData\RustDesk" -Recurse -Force -ErrorAction SilentlyContinue

# 重新编译
cd libs\portable
cargo clean
cargo build --release

# 重新测试
cd tests
.\quick-test.ps1
```

## 测试报告

测试完成后，可以生成报告：

```powershell
# 运行测试并保存结果
.\test-portable.ps1 | Tee-Object -FilePath "test-results.txt"

# 查看摘要
Get-Content "test-results.txt" | Select-String -Pattern "TEST SUMMARY" -Context 0,20
```

## 贡献测试用例

如果你发现新的测试场景，请：

1. 在 `test-portable.ps1` 中添加测试用例
2. 更新 `TEST_PLAN.md` 文档
3. 运行所有测试确保通过
4. 提交 Pull Request

## 相关文档

- 📋 [详细测试计划](./TEST_PLAN.md) - 包含所有测试场景和设计思路
- 🔧 [快速测试脚本](./quick-test.ps1) - 8步核心功能测试
- 📊 [完整测试套件](./test-portable.ps1) - 14个详细测试用例

## 获取帮助

如果遇到测试问题：

1. 查看 [TEST_PLAN.md](./TEST_PLAN.md) 中的故障排查部分
2. 检查日志文件: `C:\ProgramData\RustDesk\log\portable-packer\`
3. 提交 Issue 并附上测试输出和日志
