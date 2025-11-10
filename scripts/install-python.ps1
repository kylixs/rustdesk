# Python 3 安装脚本 (PowerShell for Windows)
# 支持自动下载和安装 Python 3.11.x

param(
    [string]$Version = "3.11.9",
    [string]$InstallDir = "",
    [switch]$Silent,
    [switch]$SkipPath,
    [switch]$Help
)

# 颜色函数
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Write-Section {
    param([string]$Message)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host $Message -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
}

# 显示帮助
if ($Help) {
    Write-Host "Python 3 安装脚本 (PowerShell)"
    Write-Host ""
    Write-Host "用法: .\install-python.ps1 [选项]"
    Write-Host ""
    Write-Host "参数:"
    Write-Host "  -Version <ver>       指定 Python 版本 (默认: 3.11.9)"
    Write-Host "  -InstallDir <dir>    自定义安装目录"
    Write-Host "  -Silent              静默安装,不显示安装界面"
    Write-Host "  -SkipPath            不添加到 PATH"
    Write-Host "  -Help                显示此帮助信息"
    Write-Host ""
    Write-Host "示例:"
    Write-Host "  .\install-python.ps1"
    Write-Host "  .\install-python.ps1 -Version 3.12.0"
    Write-Host "  .\install-python.ps1 -Silent"
    Write-Host "  .\install-python.ps1 -InstallDir C:\Python311"
    exit 0
}

# Python 版本配置
$PythonVersion = $Version
$PythonMajorMinor = ($Version -split '\.')[0,1] -join '.'
$PythonInstaller = "python-$PythonVersion-amd64.exe"
$DownloadUrl = "https://www.python.org/ftp/python/$PythonVersion/$PythonInstaller"

# 默认安装目录
if ([string]::IsNullOrEmpty($InstallDir)) {
    $InstallDir = "C:\Python$($PythonMajorMinor -replace '\.','')"
}

Write-Section "Python 3 安装脚本"
Write-Info "Python 版本: $PythonVersion"
Write-Info "安装目录: $InstallDir"
Write-Info "静默安装: $Silent"

# 检查管理员权限
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Warning "未以管理员权限运行,某些功能可能受限"
    Write-Info "建议右键点击 PowerShell 并选择 '以管理员身份运行'"
}

# 检查 Python 是否已安装
Write-Section "检查 Python 安装状态"

$PythonCmd = Get-Command python -ErrorAction SilentlyContinue
if ($PythonCmd) {
    $ExistingVersion = (python --version 2>&1) -replace 'Python ',''
    Write-Warning "检测到已安装的 Python: $ExistingVersion"
    Write-Info "路径: $($PythonCmd.Source)"

    $Continue = Read-Host "是否继续安装 Python $PythonVersion? (y/N)"
    if ($Continue -notmatch '^[Yy]$') {
        Write-Info "安装已取消"
        exit 0
    }
} else {
    Write-Info "未检测到 Python 安装"
}

# 下载 Python 安装程序
Write-Section "下载 Python 安装程序"

if (Test-Path $PythonInstaller) {
    Write-Warning "安装程序已存在: $PythonInstaller"

    $UseExisting = Read-Host "是否使用现有文件? (Y/n)"
    if ($UseExisting -match '^[Nn]$') {
        Write-Info "删除旧文件,重新下载..."
        Remove-Item $PythonInstaller -Force
        $SkipDownload = $false
    } else {
        Write-Info "使用现有安装程序"
        $SkipDownload = $true
    }
} else {
    $SkipDownload = $false
}

if (-not $SkipDownload) {
    Write-Info "正在下载 Python $PythonVersion..."
    Write-Info "下载地址: $DownloadUrl"

    try {
        # 使用 BITS 传输 (后台智能传输服务)
        Import-Module BitsTransfer
        Start-BitsTransfer -Source $DownloadUrl -Destination $PythonInstaller -Description "下载 Python $PythonVersion"
        Write-Success "下载完成: $PythonInstaller"
    } catch {
        Write-Warning "BITS 传输失败,尝试使用 Invoke-WebRequest..."
        try {
            Invoke-WebRequest -Uri $DownloadUrl -OutFile $PythonInstaller -UseBasicParsing
            Write-Success "下载完成: $PythonInstaller"
        } catch {
            Write-Error "下载失败: $_"
            Write-Info "请手动下载: $DownloadUrl"
            exit 1
        }
    }

    if (Test-Path $PythonInstaller) {
        $FileSize = (Get-Item $PythonInstaller).Length / 1MB
        Write-Success "文件大小: $([math]::Round($FileSize, 2)) MB"
    }
}

# 验证安装程序
Write-Section "验证安装程序"

$FileInfo = Get-Item $PythonInstaller
if ($FileInfo.Length -lt 1MB) {
    Write-Error "安装程序文件异常,大小: $($FileInfo.Length) 字节"
    Write-Info "请删除并重新下载"
    exit 1
}

Write-Success "安装程序验证通过"

# 准备安装参数
Write-Section "准备安装"

$InstallArgs = @(
    "/passive",
    "InstallAllUsers=0",
    "PrependPath=1",
    "Include_test=0",
    "TargetDir=$InstallDir"
)

if ($Silent) {
    $InstallArgs[0] = "/quiet"
}

if ($SkipPath) {
    $InstallArgs = $InstallArgs | ForEach-Object {
        if ($_ -eq "PrependPath=1") {
            "PrependPath=0"
        } else {
            $_
        }
    }
}

Write-Info "安装参数: $($InstallArgs -join ' ')"

# 执行安装
Write-Section "安装 Python"

Write-Info "开始安装 Python $PythonVersion..."
if ($Silent) {
    Write-Warning "静默安装中,请稍候..."
} else {
    Write-Warning "将显示安装进度,请勿关闭窗口"
}

try {
    $Process = Start-Process -FilePath ".\$PythonInstaller" -ArgumentList $InstallArgs -Wait -PassThru

    if ($Process.ExitCode -eq 0) {
        Write-Success "Python 安装完成"
    } elseif ($Process.ExitCode -eq 3010) {
        Write-Warning "安装完成,但需要重启系统"
    } else {
        Write-Error "安装失败,退出代码: $($Process.ExitCode)"
        exit 1
    }
} catch {
    Write-Error "安装过程中出错: $_"
    exit 1
}

# 等待安装完成
Start-Sleep -Seconds 5

# 刷新环境变量
Write-Info "刷新环境变量..."
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# 同时添加预期的安装目录
$env:Path = "$InstallDir;$InstallDir\Scripts;$env:Path"

# 尝试常见的 Python 安装位置
$PythonMajorMinorNoDot = ($PythonVersion -split '\.')[0,1] -join ''
$PossiblePythonPaths = @(
    $InstallDir,
    "$env:LOCALAPPDATA\Programs\Python\Python$PythonMajorMinorNoDot",
    "C:\Python$PythonMajorMinorNoDot",
    "C:\Program Files\Python$PythonMajorMinorNoDot"
)

$FoundPythonPath = $null
foreach ($PyPath in $PossiblePythonPaths) {
    if (Test-Path "$PyPath\python.exe") {
        Write-Info "找到 Python 安装位置: $PyPath"
        $env:Path = "$PyPath;$PyPath\Scripts;$env:Path"
        $FoundPythonPath = $PyPath
        break
    }
}

# 验证安装
Write-Section "验证安装"

# 检查 Python
Write-Info "检查 Python..."
$PythonExe = Join-Path $InstallDir "python.exe"

if (Get-Command python -ErrorAction SilentlyContinue) {
    $InstalledVersion = python --version 2>&1
    Write-Success "Python 已安装: $InstalledVersion"
    Write-Success "PATH 已刷新"
} elseif ($FoundPythonPath -and (Test-Path "$FoundPythonPath\python.exe")) {
    $InstalledVersion = & "$FoundPythonPath\python.exe" --version 2>&1
    Write-Success "Python 已安装: $InstalledVersion"
    Write-Warning "Python 未在当前 PATH 中,但已找到安装位置"
    Write-Info "路径: $FoundPythonPath"
} elseif (Test-Path $PythonExe) {
    $InstalledVersion = & $PythonExe --version 2>&1
    Write-Success "Python 已安装: $InstalledVersion"
    Write-Warning "Python 不在当前 PATH 中"
    Write-Info "安装目录: $InstallDir"
} else {
    Write-Error "Python 安装验证失败"
    Write-Info "请检查安装目录: $InstallDir"
}

# 检查 pip
Write-Info "检查 pip..."
$PipExe = Join-Path (Join-Path $InstallDir "Scripts") "pip.exe"

if (Get-Command pip -ErrorAction SilentlyContinue) {
    $PipVersion = pip --version 2>&1
    Write-Success "pip 已安装: $PipVersion"
} elseif (Test-Path $PipExe) {
    $PipVersion = & $PipExe --version 2>&1
    Write-Success "pip 已安装: $PipVersion"
} else {
    Write-Warning "pip 未找到"
}

# 升级 pip
if ((Get-Command pip -ErrorAction SilentlyContinue) -or (Test-Path $PipExe)) {
    Write-Section "升级 pip"

    Write-Info "升级 pip 到最新版本..."
    try {
        if (Get-Command python -ErrorAction SilentlyContinue) {
            python -m pip install --upgrade pip | Out-Null
        } else {
            & $PythonExe -m pip install --upgrade pip | Out-Null
        }
        Write-Success "pip 已升级"
    } catch {
        Write-Warning "pip 升级失败: $_"
    }
}

# 安装常用包
Write-Section "安装常用 Python 包 (可选)"

$InstallPackages = Read-Host "是否安装构建所需的 Python 包? (requests, argparse) (Y/n)"
if ($InstallPackages -notmatch '^[Nn]$') {
    Write-Info "安装 requests 和 argparse..."

    try {
        if (Get-Command pip -ErrorAction SilentlyContinue) {
            pip install requests argparse | Out-Null
        } else {
            & $PipExe install requests argparse | Out-Null
        }
        Write-Success "Python 包安装完成"
    } catch {
        Write-Warning "包安装失败: $_"
    }
}

# 清理安装程序
Write-Section "清理"

$DeleteInstaller = Read-Host "是否删除安装程序? (Y/n)"
if ($DeleteInstaller -notmatch '^[Nn]$') {
    Remove-Item $PythonInstaller -Force
    Write-Success "安装程序已删除"
} else {
    Write-Info "保留安装程序: $PythonInstaller"
}

# 环境变量配置指南
Write-Section "环境变量配置"

if ($SkipPath -or -not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Warning "Python 未添加到 PATH,需要手动配置"
    Write-Host ""
    Write-Info "添加到 Windows 环境变量:"
    Write-Host "1. 打开 '系统属性' -> '高级' -> '环境变量'"
    Write-Host "2. 在 '用户变量' 中编辑 'Path'"
    Write-Host "3. 添加以下路径:"
    Write-Host "   - $InstallDir"
    Write-Host "   - $InstallDir\Scripts"
    Write-Host ""
    Write-Info "或在 PowerShell 中执行 (临时):"
    Write-Host "`$env:Path += `";$InstallDir;$InstallDir\Scripts`""
    Write-Host ""
} else {
    Write-Success "Python 已添加到系统 PATH"
}

# 安装总结
Write-Section "安装完成"

Write-Success "Python $PythonVersion 安装成功!"
Write-Host ""
Write-Info "安装信息:"
Write-Host "  安装目录: $InstallDir"

if (Get-Command python -ErrorAction SilentlyContinue) {
    $PythonInfo = Get-Command python
    Write-Host "  Python 版本: $(python --version 2>&1)"
    Write-Host "  Python 路径: $($PythonInfo.Source)"
} elseif (Test-Path $PythonExe) {
    Write-Host "  Python 版本: $(& $PythonExe --version 2>&1)"
    Write-Host "  Python 路径: $PythonExe"
}

if (Get-Command pip -ErrorAction SilentlyContinue) {
    $PipInfo = Get-Command pip
    $PipVer = (pip --version 2>&1) -replace '.*pip ([\d\.]+).*','$1'
    Write-Host "  pip 版本: $PipVer"
    Write-Host "  pip 路径: $($PipInfo.Source)"
} elseif (Test-Path $PipExe) {
    $PipVer = (& $PipExe --version 2>&1) -replace '.*pip ([\d\.]+).*','$1'
    Write-Host "  pip 版本: $PipVer"
    Write-Host "  pip 路径: $PipExe"
}

Write-Host ""
Write-Info "下一步:"
Write-Host "  1. 验证安装: python --version"
Write-Host "  2. 验证 pip: pip --version"
Write-Host "  3. 升级 pip: python -m pip install --upgrade pip"
Write-Host "  4. 安装包: pip install <package-name>"
Write-Host ""

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Warning "注意: 如果在新终端中无法使用 python 命令:"
    Write-Host "  - 重启 PowerShell 或命令提示符"
    Write-Host "  - 或使用完整路径: $PythonExe"
}

Write-Success "安装脚本执行完毕!"
