# 安装 vcpkg 依赖脚本
# 用于手动安装或重新安装 vcpkg 依赖

param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

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

# 检查 VCPKG_ROOT
$VCPKG_ROOT = if ($env:VCPKG_ROOT) { $env:VCPKG_ROOT } else { "C:\vcpkg" }

if (-not (Test-Path $VCPKG_ROOT)) {
    Write-Error "vcpkg 未安装在: $VCPKG_ROOT"
    Write-Info "请先运行 scripts\setup-env.ps1 安装 vcpkg"
    exit 1
}

if (-not (Test-Path "$VCPKG_ROOT\vcpkg.exe")) {
    Write-Error "vcpkg.exe 未找到: $VCPKG_ROOT\vcpkg.exe"
    exit 1
}

# 检查 vcpkg.json
if (-not (Test-Path ".\vcpkg.json")) {
    Write-Error "vcpkg.json 未找到，请确保在 RustDesk 项目根目录运行此脚本"
    exit 1
}

# 设置环境变量
$env:VCPKG_ROOT = $VCPKG_ROOT
$env:VCPKG_DEFAULT_HOST_TRIPLET = "x64-windows-static"

Write-Info "========================================="
Write-Info "安装 vcpkg 依赖"
Write-Info "========================================="
Write-Info "vcpkg Root: $VCPKG_ROOT"
Write-Info "Triplet: x64-windows-static"
Write-Info ""

# 检查已安装的包
Write-Info "检查已安装的包..."
$InstalledPackages = & "$VCPKG_ROOT\vcpkg.exe" list

$RequiredPackages = @("opus", "libvpx", "libyuv", "aom")
$MissingPackages = @()

foreach ($Package in $RequiredPackages) {
    if ($InstalledPackages -match "$Package`:x64-windows-static") {
        Write-Success "$Package 已安装"
    } else {
        Write-Warning "$Package 未安装"
        $MissingPackages += $Package
    }
}

if ($MissingPackages.Count -eq 0 -and -not $Force) {
    Write-Success "所有必需的包都已安装"
    Write-Info "如需重新安装，请使用 -Force 参数"
    exit 0
}

if ($Force) {
    Write-Warning "强制重新安装所有依赖..."
}

Write-Info ""
Write-Warning "这可能需要 30-60 分钟，请耐心等待..."
Write-Info "开始安装依赖..."
Write-Info ""

# 使用 vcpkg install 根据 vcpkg.json 安装
try {
    # vcpkg 会自动读取当前目录的 vcpkg.json
    & "$VCPKG_ROOT\vcpkg.exe" install --triplet x64-windows-static --x-install-root="$VCPKG_ROOT\installed"

    if ($LASTEXITCODE -eq 0) {
        Write-Info ""
        Write-Success "========================================="
        Write-Success "vcpkg 依赖安装成功!"
        Write-Success "========================================="
        Write-Info ""

        # 验证关键文件
        Write-Info "验证安装..."
        $VerificationFiles = @(
            "$VCPKG_ROOT\installed\x64-windows-static\include\opus\opus.h",
            "$VCPKG_ROOT\installed\x64-windows-static\include\opus\opus_multistream.h",
            "$VCPKG_ROOT\installed\x64-windows-static\lib\opus.lib",
            "$VCPKG_ROOT\installed\x64-windows-static\lib\vpx.lib",
            "$VCPKG_ROOT\installed\x64-windows-static\lib\yuv.lib"
        )

        $AllFilesExist = $true
        foreach ($File in $VerificationFiles) {
            if (Test-Path $File) {
                Write-Success "✓ $(Split-Path -Leaf $File)"
            } else {
                Write-Warning "✗ $(Split-Path -Leaf $File) 未找到"
                $AllFilesExist = $false
            }
        }

        if ($AllFilesExist) {
            Write-Info ""
            Write-Success "所有关键文件验证通过"
            Write-Info "现在可以运行 build-rustdesk.ps1 构建项目"
        } else {
            Write-Warning "部分文件缺失，可能需要重新安装"
        }
    } else {
        Write-Error ""
        Write-Error "========================================="
        Write-Error "vcpkg 依赖安装失败"
        Write-Error "========================================="
        Write-Info "检查日志："

        if (Test-Path "$VCPKG_ROOT\buildtrees") {
            Get-ChildItem "$VCPKG_ROOT\buildtrees" -Filter "*.log" -Recurse -ErrorAction SilentlyContinue |
                Select-Object -First 5 |
                ForEach-Object {
                    Write-Host "  - $($_.FullName)"
                }
        }

        exit 1
    }
} catch {
    Write-Error "安装过程中发生错误: $_"
    exit 1
}
