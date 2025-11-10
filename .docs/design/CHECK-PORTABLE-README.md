# Portable Package Verification Script

用于检查 RustDesk Portable 包中所有文件的版本、MD5 哈希值和大小信息。

## 功能特性

- ✅ **自动检测 Portable 目录**：智能查找常见的解压位置
- ✅ 检查所有文件的 MD5 哈希值
- ✅ 读取 EXE/DLL 文件的版本信息
- ✅ 显示文件大小（自动格式化）
- ✅ 按文件名排序输出
- ✅ 支持多种输出格式（文本/CSV/JSON）
- ✅ 跨平台支持（Windows PowerShell / Linux/macOS Bash）

## Portable 目录检测逻辑

脚本通过多种方法智能检测 portable 解压目录，优先级顺序：

### 检测方法（按优先级）

1. **运行进程检测** 🔍
   - 检测正在运行的 `rustdesk.exe` 进程
   - 获取进程所在目录
   - 验证目录包含 `rustdesk.exe` 和 `data/` 目录
   - **最准确**：直接定位到实际运行的 portable 目录

2. **端口检测** 🌐
   - 检测 RustDesk 监听端口（21118、21119）
   - 通过端口找到对应进程
   - 获取进程目录
   - **适用场景**：进程名称被修改的情况
   - **注意**：需要管理员权限

3. **标准路径** 📁
   - Fallback 到标准解压路径：`%LOCALAPPDATA%\rustdesk\`
   - 通常路径：`C:\Users\<用户名>\AppData\Local\rustdesk\`
   - 遵循 portable 程序逻辑（`libs/portable/src/main.rs`）
   - 对应代码：`dirs::data_local_dir().join("rustdesk")`

### 使用模式

- **默认模式**：静默使用方法 1 和 3，无详细输出
- **-AutoDetect**：显示所有检测方法的详细进度
- **手动指定**：直接指定路径参数，跳过自动检测

### 优势

✅ 自动适应不同安装场景
✅ 支持服务模式和用户模式
✅ 处理自定义安装路径
✅ 优先使用实际运行进程，确保准确性

## 使用方法

### Windows (PowerShell)

```powershell
# 自动检测 portable 目录（推荐）
.\scripts\check-portable.ps1 -AutoDetect

# 基本使用（优先从运行进程检测）
.\scripts\check-portable.ps1

# 检查指定目录
.\scripts\check-portable.ps1 .\rustdesk

# 输出到 CSV 文件（正确方法，避免编码问题）
.\scripts\check-portable.ps1 -Csv | Out-File -Encoding UTF8 files.csv

# 输出到 JSON 文件（正确方法，避免编码问题）
.\scripts\check-portable.ps1 -Json | Out-File -Encoding UTF8 files.json

# 或者使用重定向（PowerShell 默认 UTF-16 编码）
.\scripts\check-portable.ps1 -Csv > files.csv

# 查看帮助
.\scripts\check-portable.ps1 -Help
```

### Linux/macOS (Bash)

```bash
# 基本使用
./scripts/check-portable.sh

# 检查指定目录
./scripts/check-portable.sh ./rustdesk

# 输出到 CSV 文件
./scripts/check-portable.sh ./rustdesk csv > files.csv

# 输出到 JSON 文件
./scripts/check-portable.sh ./rustdesk json > files.json

# 查看帮助
./scripts/check-portable.sh --help
```

## 输出重定向

### PowerShell 输出重定向注意事项

**方法 1：使用 Out-File 指定编码**（推荐）
```powershell
# UTF-8 编码（推荐，兼容性最好）
.\scripts\check-portable.ps1 -Csv | Out-File -Encoding UTF8 files.csv
.\scripts\check-portable.ps1 -Json | Out-File -Encoding UTF8 files.json
.\scripts\check-portable.ps1 | Out-File -Encoding UTF8 output.txt
```

**方法 2：PowerShell Core (7+) 使用 UTF-8**
```powershell
# PowerShell 7+ 默认使用 UTF-8（无 BOM）
# 下载安装：https://github.com/PowerShell/PowerShell/releases
pwsh -Command ".\scripts\check-portable.ps1 -Csv > files.csv"
```

**方法 3：直接重定向（PowerShell 5.1 固定 UTF-16）**
```powershell
# 使用 > 重定向（UTF-16 LE with BOM）
.\scripts\check-portable.ps1 -Csv > files.csv
.\scripts\check-portable.ps1 -Json > files.json

# 注意：PowerShell 5.1 默认使用 UTF-16 编码
# 大多数工具（Excel、记事本等）都能正确处理 UTF-16
```

**编码说明**：
- **PowerShell 5.1**：`>` 重定向**固定**使用 UTF-16 LE（无法通过设置改变）
- **PowerShell 7+**：`>` 重定向默认使用 UTF-8（无 BOM）
- **兼容性**：UTF-8 兼容性更好，适合跨平台和 Unix 工具
- **最佳实践**：
  - **推荐**：使用 `Out-File -Encoding UTF8` 明确指定编码
  - **简单**：如果只在 Windows 使用，直接 `>` 重定向即可（Excel、记事本都支持 UTF-16）
  - **跨平台**：升级到 PowerShell 7+ 或使用 `Out-File`

## 输出格式

### 文本格式（默认）

```
========================================================================================================================
File                                               Version              MD5                                    Size
========================================================================================================================
rustdesk.exe                                       1.4.3+61             4595b89cb0130722409e0f9d427296b0   263.00KB
libsciter.dll                                      4.4.8.30             e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0     8.50MB
data\flutter_assets\AssetManifest.bin              -                    baebbc9a046334ade579a9d689954633     4.06KB
...
========================================================================================================================
Total: 90 files
Total size: 69.82MB
```

**说明**：
- EXE/DLL 文件显示为绿色/黄色高亮
- 版本信息从 PE 文件头读取
- 非 PE 文件的版本显示为 `-`

### CSV 格式

```csv
Path,Version,MD5,Size
rustdesk.exe,1.4.3+61,4595b89cb0130722409e0f9d427296b0,268800
libsciter.dll,4.4.8.30,e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0,8912896
data\flutter_assets\AssetManifest.bin,-,baebbc9a046334ade579a9d689954633,4157
```

**用途**：
- 导入 Excel 进行分析
- 使用脚本自动化处理
- 版本对比工具

### JSON 格式

```json
{
  "directory": "C:\\rustdesk",
  "timestamp": "2025-01-21 14:30:00",
  "file_count": 90,
  "files": [
    {
      "path": "rustdesk.exe",
      "version": "1.4.3+61",
      "md5": "4595b89cb0130722409e0f9d427296b0",
      "size": 268800
    },
    ...
  ]
}
```

**用途**：
- 程序化处理
- API 集成
- 自动化测试

## 使用场景

### 1. 版本对比

比较两个 portable 包的差异：

```powershell
# 生成两个版本的报告
.\scripts\check-portable.ps1 .\rustdesk-v1 -Csv > v1.csv
.\scripts\check-portable.ps1 .\rustdesk-v2 -Csv > v2.csv

# 使用 diff 工具对比
diff v1.csv v2.csv
```

### 2. 完整性验证

验证解压后的文件是否完整：

```powershell
# 生成标准清单
.\scripts\check-portable.ps1 .\rustdesk-master -Csv > master.csv

# 验证新构建
.\scripts\check-portable.ps1 .\rustdesk-new -Csv > new.csv
diff master.csv new.csv
```

### 3. CI/CD 集成

在构建流程中自动验证：

```powershell
# 构建后验证
.\build.ps1
$result = .\scripts\check-portable.ps1 -Json | ConvertFrom-Json

# 检查关键文件
$rustdesk = $result.files | Where-Object { $_.path -eq "rustdesk.exe" }
if ($rustdesk.version -ne $env:EXPECTED_VERSION) {
    Write-Error "Version mismatch!"
    exit 1
}
```

### 4. 问题诊断

用户报告问题时收集信息：

```powershell
# 生成完整报告
.\scripts\check-portable.ps1 -Json > diagnostic-report.json

# 发送给技术支持
```

## 输出说明

### 版本字段

- **有版本号**：从 PE 文件头读取（格式：`1.4.3+61`）
- **无版本号**：显示 `-`（非 PE 文件或无版本信息）

### MD5 字段

- **32 位十六进制字符串**：文件内容的 MD5 哈希值
- **小写**：统一使用小写字母
- **用途**：验证文件完整性和一致性

### Size 字段

- **文本格式**：自动格式化（B/KB/MB/GB）
- **CSV/JSON**：原始字节数
- **精度**：两位小数

## 性能

- **小型包** (< 100 文件)：< 5 秒
- **中型包** (< 500 文件)：< 20 秒
- **大型包** (> 1000 文件)：< 60 秒

性能主要取决于：
1. 文件数量
2. 文件总大小
3. 磁盘 I/O 速度

## 技术细节

### Windows (PowerShell)

- 版本读取：`[System.Diagnostics.FileVersionInfo]::GetVersionInfo()`
- MD5 计算：`System.Security.Cryptography.MD5CryptoServiceProvider`
- 兼容性：PowerShell 5.1+

### Linux/macOS (Bash)

- 版本读取：`strings` 命令提取
- MD5 计算：`md5sum` (Linux) 或 `md5` (macOS)
- 兼容性：Bash 4.0+

## 限制和注意事项

1. **版本信息**
   - 仅支持 PE 文件（EXE/DLL）
   - Linux/macOS 上的版本读取准确性较低
   - 某些文件可能没有版本信息

2. **性能**
   - MD5 计算对大文件较慢
   - 建议在 SSD 上运行以获得最佳性能

3. **跨平台**
   - Windows 脚本功能更完整
   - Linux/macOS 脚本为简化版本

## 故障排除

### PowerShell 执行策略错误

```powershell
# 临时允许脚本执行
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# 或使用完整命令
powershell -ExecutionPolicy Bypass -File .\scripts\check-portable.ps1
```

### Linux/macOS 权限错误

```bash
# 添加执行权限
chmod +x scripts/check-portable.sh
```

### 缺少命令

```bash
# Linux: 安装必要工具
sudo apt install coreutils bc

# macOS: 使用 Homebrew
brew install coreutils
```

## 示例输出

### 完整示例（文本格式）

```
Scanning directory: C:\Users\user\rustdesk
Found 90 files

========================================================================================================================
File                                               Version              MD5                                    Size
========================================================================================================================
data\app.so                                        -                    a6b51bc82979435ce12efddfad3af9f7    12.49MB
data\flutter_assets\AssetManifest.bin              -                    baebbc9a046334ade579a9d689954633     4.06KB
rustdesk.exe                                       1.4.3.61             4595b89cb0130722409e0f9d427296b0   263.00KB
libsciter.dll                                      4.4.8.30             e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0     8.50MB
========================================================================================================================
Total: 90 files
Total size: 69.82MB
```

## 常见用法总结

```powershell
# 1. 快速检查当前目录
.\scripts\check-portable.ps1

# 2. 导出到 CSV 用于 Excel 分析
.\scripts\check-portable.ps1 -Csv > analysis.csv

# 3. 导出到 JSON 用于自动化
.\scripts\check-portable.ps1 -Json > report.json

# 4. 对比两个版本
diff (.\scripts\check-portable.ps1 v1 -Csv) (.\scripts\check-portable.ps1 v2 -Csv)

# 5. 仅检查 EXE/DLL 文件
.\scripts\check-portable.ps1 -Csv | Select-String "\.exe,|\.dll,"
```

---

**脚本位置**：
- Windows: `scripts/check-portable.ps1`
- Linux/macOS: `scripts/check-portable.sh`

**作者**：RustDesk Team
**更新日期**：2025-01-21
