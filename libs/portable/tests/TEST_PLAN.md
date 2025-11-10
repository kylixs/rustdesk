# RustDesk Portable Packer Test Plan

## 测试目标

验证以下核心功能：
1. ✅ 进程检测只执行一次（性能优化）
2. ✅ Manifest 与 Portable Data 一致性检查
3. ✅ 同版本不同构建时间的处理
4. ✅ 文件损坏的自动恢复
5. ✅ 有进程运行时的安全保护
6. ✅ --repair 命令的强制修复功能

## 测试环境

- **操作系统**: Windows 10/11
- **测试工具**: PowerShell 5.1+
- **前置条件**: 已编译 `rustdesk-portable-packer.exe`

## 测试脚本

### 1. 完整测试套件 (test-portable.ps1)

包含 14 个详细测试用例，覆盖所有功能场景。

**运行方式：**
```powershell
# 使用默认路径
.\test-portable.ps1

# 指定可执行文件路径
.\test-portable.ps1 -PortableExe "C:\path\to\rustdesk-portable-packer.exe"

# 启用详细输出
.\test-portable.ps1 -Verbose
```

**测试用例列表：**

| # | 测试用例 | 描述 | 验证点 |
|---|---------|------|--------|
| 1 | Initial Extraction | 首次解压安装 | 文件正确解压、manifest生成 |
| 2 | Normal Startup | 正常启动（无变化） | 启动速度快、跳过文件写入 |
| 3 | Timestamp Mismatch (No Process) | 构建时间不匹配（无进程） | 自动重新解压 |
| 4 | Timestamp Mismatch (With Process) | 构建时间不匹配（有进程） | 安全失败、提示修复 |
| 5 | Manifest Inconsistency (No Process) | Manifest不一致（无进程） | 自动重新生成 |
| 6 | Manifest Inconsistency (With Process) | Manifest不一致（有进程） | 安全失败、提示修复 |
| 7 | File Corruption (No Process) | 文件损坏（无进程） | 自动恢复文件 |
| 8 | File Corruption (With Process) | 文件损坏（有进程） | 安全失败、提示修复 |
| 9 | Manual Repair | --repair 命令 | 强制修复成功 |
| 10 | Repair With Process | --repair（有进程） | 停止进程并修复 |
| 11 | Verify Command | --verify 验证 | 验证通过 |
| 12 | Verify After Corruption | 损坏后验证 | 检测到损坏 |
| 13 | Dump Manifest | --dump-manifest | 显示manifest内容 |
| 14 | Performance Check | 性能验证 | 进程检查只执行一次 |

### 2. 快速测试 (quick-test.ps1)

简化的测试套件，快速验证核心功能（约30秒）。

**运行方式：**
```powershell
.\quick-test.ps1
```

**测试步骤：**
1. 清理环境
2. 初始解压
3. 正常启动性能测试
4. 文件验证
5. 文件损坏与自动恢复
6. 手动修复命令
7. Manifest 显示
8. 进程检测

## 测试场景详解

### 场景 1: 首次安装（干净环境）

```
状态: 目标目录不存在
操作: 运行 rustdesk-portable-packer.exe
预期:
  - 创建解压目录 C:\ProgramData\RustDesk\bin\{VERSION}\
  - 解压所有文件
  - 生成 manifest
  - 生成 meta.toml
结果: ✅ 所有文件正确解压
```

### 场景 2: 正常启动（无变化）

```
状态: 文件完整，timestamp匹配，manifest一致
操作: 再次运行
预期:
  - 跳过文件解压
  - 快速验证文件完整性
  - 启动时间 < 2秒
结果: ✅ 启动快速，无不必要的文件操作
```

### 场景 3: 同版本重新构建（无进程）

```
状态: 版本相同，但 timestamp 不同
操作: 运行 portable packer
预期:
  - 检测到 timestamp 不匹配
  - 检查进程：无运行进程
  - 自动清空目录
  - 重新解压所有文件
结果: ✅ 自动更新成功
```

### 场景 4: 同版本重新构建（有进程）

```
状态: 版本相同，timestamp 不同，rustdesk.exe 正在运行
操作: 运行 portable packer
预期:
  - 检测到 timestamp 不匹配
  - 检查进程：发现运行中的 rustdesk.exe
  - 显示错误信息
  - 提示执行 --repair 命令
  - 退出（不修改任何文件）
结果: ✅ 安全失败，提供清晰的修复指导
```

### 场景 5: Manifest 损坏（无进程）

```
状态: .rustdesk_manifest.bin 被删除或损坏
操作: 运行 portable packer
预期:
  - 检测到 manifest 缺失
  - 检查进程：无运行进程
  - 自动重新生成 manifest
  - 继续正常启动
结果: ✅ 自动恢复
```

### 场景 6: Manifest 损坏（有进程）

```
状态: manifest 损坏，有进程运行
操作: 运行 portable packer
预期:
  - 检测到 manifest 问题
  - 检查进程：发现运行进程
  - 显示错误信息
  - 提示执行 --repair
  - 退出（不修改文件）
结果: ✅ 安全失败
```

### 场景 7: 文件损坏（无进程）

```
状态: rustdesk.exe 被损坏
操作: 运行 portable packer
预期:
  - 验证文件完整性失败
  - 检查进程：无运行进程
  - 自动从 portable data 恢复文件
  - 更新 manifest
  - 继续启动
结果: ✅ 自动修复成功
```

### 场景 8: 文件损坏（有进程）

```
状态: rustdesk.exe 损坏，进程占用
操作: 运行 portable packer
预期:
  - 检测到文件损坏
  - 检查进程：发现运行进程
  - 显示错误信息
  - 提示执行 --repair
  - 退出（不尝试修复）
结果: ✅ 安全失败，避免破坏运行中的程序
```

### 场景 9: 手动修复命令

```
状态: 任意损坏状态
操作: rustdesk-portable-packer.exe --repair
预期:
  - 检测运行中的进程
  - 强制停止所有进程
  - 清空目录
  - 重新解压所有文件
  - 重新生成 manifest
结果: ✅ 强制修复成功
```

### 场景 10: 性能验证

```
测试: 进程检查只执行一次
方法: 启用 debug 日志，检查日志输出
预期:
  - "Process check" 只出现 1 次
  - 每次检查耗时 < 5ms
结果: ✅ 性能优化生效
```

## 预期测试结果

### 成功标准

- ✅ 所有 14 个测试用例通过
- ✅ 无进程运行时，所有问题自动修复
- ✅ 有进程运行时，安全失败并提示
- ✅ --repair 命令能修复所有问题
- ✅ 进程检测只执行一次
- ✅ 启动性能 < 2秒（文件未变化时）

### 失败处理

如果测试失败：
1. 查看详细错误信息
2. 检查日志文件: `C:\ProgramData\RustDesk\log\portable-packer\`
3. 手动清理: 删除 `C:\ProgramData\RustDesk\bin\{VERSION}\`
4. 重新运行测试

## 手动测试步骤

### 测试 1: 基础功能

```powershell
# 1. 清理
Remove-Item -Path "C:\ProgramData\RustDesk\bin\*" -Recurse -Force

# 2. 首次运行
.\target\release\rustdesk-portable-packer.exe --version

# 3. 验证
.\target\release\rustdesk-portable-packer.exe --verify

# 4. 查看 manifest
.\target\release\rustdesk-portable-packer.exe --dump-manifest
```

### 测试 2: 进程冲突

```powershell
# 1. 正常启动一次
.\target\release\rustdesk-portable-packer.exe --version

# 2. 修改 timestamp 模拟重新构建
$version = "1.4.3-jlc20"  # 替换为实际版本
$metaFile = "C:\ProgramData\RustDesk\bin\$version\meta.toml"
(Get-Content $metaFile) -replace 'timestamp = \d+', 'timestamp = 9999' | Set-Content $metaFile

# 3. 启动一个 rustdesk 进程
Start-Process "C:\ProgramData\RustDesk\bin\$version\rustdesk.exe" -ArgumentList "--version"

# 4. 尝试再次运行（应该失败）
.\target\release\rustdesk-portable-packer.exe --version
# 预期: 显示错误并提示使用 --repair

# 5. 使用 --repair 修复
.\target\release\rustdesk-portable-packer.exe --repair
# 预期: 停止进程并修复成功
```

### 测试 3: 文件损坏恢复

```powershell
# 1. 损坏文件
$version = "1.4.3-jlc20"
$exePath = "C:\ProgramData\RustDesk\bin\$version\rustdesk.exe"
[System.IO.File]::WriteAllBytes($exePath, [byte[]]::new(100))

# 2. 运行（应该自动恢复）
.\target\release\rustdesk-portable-packer.exe --version

# 3. 验证恢复
(Get-Item $exePath).Length
# 预期: > 1MB
```

## 性能基准

| 操作 | 预期时间 | 实际测量 |
|------|---------|----------|
| 首次解压 | < 5s | ___ |
| 正常启动 | < 2s | ___ |
| 进程检测 | < 5ms | ___ |
| 文件验证 | < 100ms | ___ |
| 文件恢复 | < 1s/file | ___ |
| --repair | < 5s | ___ |

## 测试覆盖率

- [x] 进程检测功能
- [x] Timestamp 检查
- [x] Manifest 一致性验证
- [x] 文件完整性验证
- [x] 自动文件恢复
- [x] 进程占用时的安全处理
- [x] --repair 强制修复
- [x] --verify 验证命令
- [x] --dump-manifest 查看命令
- [x] 性能优化（进程检查一次）
- [x] 错误提示清晰度
- [x] 日志记录完整性

## 已知限制

1. **测试环境限制**: 需要实际编译的 portable packer 可执行文件
2. **权限要求**: 需要写入 `C:\ProgramData` 的权限
3. **进程模拟**: 某些测试可能因为文件损坏无法启动真实进程
4. **时序依赖**: 进程启动/停止需要短暂延迟

## 故障排查

### 问题 1: 测试失败 - "Failed to get version"

**原因**: portable packer 未编译或路径错误

**解决**:
```powershell
cd libs\portable
cargo build --release
cd tests
.\test-portable.ps1
```

### 问题 2: 进程无法停止

**原因**: 进程已经崩溃或卡死

**解决**:
```powershell
Get-Process -Name "rustdesk" | Stop-Process -Force
```

### 问题 3: 权限不足

**原因**: 无法写入 ProgramData

**解决**: 以管理员权限运行 PowerShell

### 问题 4: 文件被锁定

**原因**: 杀毒软件或其他程序占用

**解决**: 临时禁用杀毒软件

## 回归测试清单

在每次代码修改后运行：

- [ ] 运行 `quick-test.ps1` (必须)
- [ ] 运行 `test-portable.ps1` (推荐)
- [ ] 手动测试至少一个场景
- [ ] 检查日志文件无异常
- [ ] 性能符合基准

## 持续集成

TODO: 集成到 CI/CD pipeline

```yaml
# .github/workflows/test-portable.yml 示例
steps:
  - name: Build Portable Packer
    run: cargo build --release --manifest-path libs/portable/Cargo.toml

  - name: Run Tests
    run: |
      cd libs/portable/tests
      pwsh -File test-portable.ps1
```
