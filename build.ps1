# RustDesk Windows Flutter 构建脚本 (PowerShell for Windows)
# 基于 .docs/build/Windows_Flutter_Build_Steps.md 和 tasks.md

param(
    [switch]$SkipBridge,
    [switch]$SkipTopmost,
    [switch]$SkipDrivers,
    [switch]$SkipMSI,
    [switch]$SkipBuild,
    [switch]$SkipPortable,
    [switch]$NoHwcodec,
    [switch]$NoVram,
    [string]$Version,
    [switch]$All,
    [switch]$Help
)

# 错误时停止
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

function Write-Section {
    param([string]$Message)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host $Message -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
}

# 显示帮助
if ($Help) {
    Write-Host "RustDesk Windows Flutter 构建脚本"
    Write-Host ""
    Write-Host "用法: .\build.ps1 [选项]"
    Write-Host ""
    Write-Host "参数:"
    Write-Host "  -SkipBridge      跳过 Flutter-Rust 桥接代码生成"
    Write-Host "  -SkipTopmost     跳过 TopMostWindow 组件构建"
    Write-Host "  -SkipDrivers     跳过驱动集成"
    Write-Host "  -SkipMSI         跳过 MSI 安装包构建"
    Write-Host "  -SkipBuild       跳过编译阶段，仅生成最终程序包 (需要已有 rustdesk 目录)"
    Write-Host "  -SkipPortable    跳过生成 portable 自解压程序"
    Write-Host "  -NoHwcodec       禁用硬件编解码支持"
    Write-Host "  -NoVram          禁用 VRAM 优化"
    Write-Host "  -Version <ver>   指定版本号 (默认: 从 Cargo.toml 读取)"
    Write-Host "  -All             执行所有步骤（忽略所有环境变量控制）"
    Write-Host "  -Help            显示此帮助信息"
    Write-Host ""
    Write-Host "环境变量控制:"
    Write-Host "  BUILD_VERSION              版本号 (默认: 从 Cargo.toml 读取)"
    Write-Host "  BROTLI_COMPRESSION_LEVEL   Brotli 压缩级别，范围 0-11 (默认: 6，适中)"
    Write-Host "                             0=最快/最大, 6=适中, 11=最慢/最小"
    Write-Host ""
    Write-Host "  构建步骤控制（值为 Y/N，忽略大小写）:"
    Write-Host "  BUILD_BRIDGE     是否生成 Flutter-Rust 桥接代码 (默认: N)"
    Write-Host "  BUILD_TOPMOST    是否构建 TopMostWindow 组件 (默认: N)"
    Write-Host "  BUILD_RUSTDESK   是否编译 RustDesk 主程序 (默认: Y)"
    Write-Host "  BUILD_DRIVERS    是否集成驱动 (默认: N)"
    Write-Host "  BUILD_PORTABLE   是否生成 portable 自解压程序 (默认: Y)"
    Write-Host "  BUILD_MSI        是否构建 MSI 安装包 (默认: N)"
    Write-Host ""
    Write-Host "示例:"
    Write-Host "  .\build.ps1                                                  # 执行默认步骤（BUILD_RUSTDESK + BUILD_PORTABLE）"
    Write-Host "  .\build.ps1 -All                                             # 强制执行所有步骤"
    Write-Host "  `$env:BUILD_MSI='Y'; .\build.ps1                             # 同时构建 MSI"
    Write-Host "  `$env:BROTLI_COMPRESSION_LEVEL='11'; .\build.ps1             # 使用最高压缩（发布用）"
    Write-Host "  `$env:BROTLI_COMPRESSION_LEVEL='3'; .\build.ps1              # 使用快速压缩（开发测试用）"
    Write-Host "  `$env:BUILD_BRIDGE='Y'; `$env:BUILD_TOPMOST='Y'; .\build.ps1  # 包含 Bridge 和 TopMost"
    exit 0
}

# 从 Cargo.toml 读取版本号
function Get-CargoVersion {
    param([string]$CargoTomlPath = ".\Cargo.toml")

    if (-not (Test-Path $CargoTomlPath)) {
        Write-Error "未找到 Cargo.toml 文件: $CargoTomlPath"
        Write-Error "请确保在 RustDesk 项目根目录运行此脚本"
        exit 1
    }

    try {
        $content = Get-Content $CargoTomlPath -Raw
        # 匹配 [package] 部分中的 version，使用非贪婪模式匹配到下一个 section 或文件结尾
        if ($content -match '\[package\][\s\S]*?version\s*=\s*"([^"]+)"') {
            return $matches[1]
        } else {
            Write-Error "无法从 Cargo.toml 的 [package] 部分解析版本号"
            Write-Error "请检查 Cargo.toml 文件格式是否正确"
            exit 1
        }
    } catch {
        Write-Error "读取 Cargo.toml 时出错: $($_.Exception.Message)"
        exit 1
    }
}

# 验证版本号格式（支持 SemVer 2.0: x.y.z[-prerelease][+build]）
function Test-VersionFormat {
    param([string]$Version)

    if ([string]::IsNullOrWhiteSpace($Version)) {
        Write-Error "版本号不能为空"
        return $false
    }

    # SemVer 2.0 格式验证
    if ($Version -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z\-.]+)?(\+[0-9A-Za-z\-.]+)?$') {
        Write-Error "版本号格式不正确: $Version"
        Write-Error "支持的格式示例:"
        Write-Host "  1.4.3" -ForegroundColor Gray
        Write-Host "  1.4.3-alpha" -ForegroundColor Gray
        Write-Host "  1.4.3-jc12" -ForegroundColor Gray
        Write-Host "  1.4.3-rc.1+build.123" -ForegroundColor Gray
        return $false
    }

    return $true
}

# 读取配置值到脚本局部变量（不修改环境变量）
# 优先级：命令行参数 > 环境变量 > 默认值
$script:BUILD_VERSION = if ($Version) {
    $Version
} elseif ($env:BUILD_VERSION) {
    $env:BUILD_VERSION
} else {
    Get-CargoVersion
}

$script:VCPKG_ROOT = if ($env:VCPKG_ROOT) { $env:VCPKG_ROOT } else { "C:\vcpkg" }
$script:VCPKG_DEFAULT_HOST_TRIPLET = if ($env:VCPKG_DEFAULT_HOST_TRIPLET) { $env:VCPKG_DEFAULT_HOST_TRIPLET } else { "x64-windows-static" }
$script:BROTLI_COMPRESSION_LEVEL = if ($env:BROTLI_COMPRESSION_LEVEL) { $env:BROTLI_COMPRESSION_LEVEL } else { "6" }

# 构建步骤配置（脚本局部变量）
$script:BUILD_BRIDGE = if ($env:BUILD_BRIDGE) { $env:BUILD_BRIDGE } else { "N" }
$script:BUILD_TOPMOST = if ($env:BUILD_TOPMOST) { $env:BUILD_TOPMOST } else { "N" }
$script:BUILD_RUSTDESK = if ($env:BUILD_RUSTDESK) { $env:BUILD_RUSTDESK } else { "Y" }
$script:BUILD_DRIVERS = if ($env:BUILD_DRIVERS) { $env:BUILD_DRIVERS } else { "N" }
$script:BUILD_PORTABLE = if ($env:BUILD_PORTABLE) { $env:BUILD_PORTABLE } else { "Y" }
$script:BUILD_MSI = if ($env:BUILD_MSI) { $env:BUILD_MSI } else { "N" }

# 验证版本号格式
Write-Info "验证版本号格式..."
if (-not (Test-VersionFormat -Version $script:BUILD_VERSION)) {
    Write-Error "构建失败: 版本号格式验证不通过"
    exit 1
}
Write-Success "版本号格式验证通过: $($script:BUILD_VERSION)"

# 步骤控制：优先级为 -All > 命令行参数 > 环境变量 > 默认值
function Get-StepEnabled {
    param(
        [string]$EnvVarName,
        [bool]$SkipParam,
        [bool]$DefaultValue = $true
    )

    if ($All) {
        return $true
    }

    if ($SkipParam) {
        return $false
    }

    # 读取环境变量（此时已包含默认值或外部设置的值）
    $EnvValue = Get-Item -Path "env:$EnvVarName" -ErrorAction SilentlyContinue
    if ($null -ne $EnvValue) {
        # 支持 Y/N，忽略大小写
        return $EnvValue.Value.ToUpper() -eq "Y"
    }

    return $DefaultValue
}

$EnableBridge = Get-StepEnabled "BUILD_BRIDGE" $SkipBridge
$EnableTopmost = Get-StepEnabled "BUILD_TOPMOST" $SkipTopmost
$EnableBuild = Get-StepEnabled "BUILD_RUSTDESK" $SkipBuild
$EnableDrivers = Get-StepEnabled "BUILD_DRIVERS" $SkipDrivers
$EnablePortable = Get-StepEnabled "BUILD_PORTABLE" $SkipPortable
$EnableMSI = Get-StepEnabled "BUILD_MSI" $SkipMSI

# 构建参数
$BuildPortable = $true
$BuildHwcodec = -not $NoHwcodec
$BuildFlutter = $true
$BuildVram = -not $NoVram

Write-Section "RustDesk Windows Flutter 构建脚本"
Write-Info "版本: $($script:BUILD_VERSION)"
Write-Info "vcpkg Root: $($script:VCPKG_ROOT)"

Write-Info "构建配置:"
Write-Host "  Flutter UI: $BuildFlutter"
Write-Host "  硬件编解码: $BuildHwcodec"
Write-Host "  VRAM 优化: $BuildVram"
Write-Host ""
Write-Info "执行步骤:"
Write-Host "  桥接代码生成: $(if ($EnableBridge) {'✓'} else {'✗'})"
Write-Host "  TopMostWindow: $(if ($EnableTopmost) {'✓'} else {'✗'})"
Write-Host "  编译主程序: $(if ($EnableBuild) {'✓'} else {'✗'})"
Write-Host "  驱动集成: $(if ($EnableDrivers) {'✓'} else {'✗'})"
Write-Host "  Portable 打包: $(if ($EnablePortable) {'✓'} else {'✗'})"
Write-Host "  MSI 构建: $(if ($EnableMSI) {'✓'} else {'✗'})"

# 检查必需工具
Write-Section "检查构建环境"

$RequiredTools = @("git", "python", "rustc", "cargo", "flutter")
foreach ($Tool in $RequiredTools) {
    if (-not (Get-Command $Tool -ErrorAction SilentlyContinue)) {
        Write-Error "$Tool 未找到,请先运行 scripts\setup-env.ps1 初始化环境"
        exit 1
    }
}

Write-Success "构建环境检查完成"

# Task 12: 生成 Flutter-Rust 桥接代码
if ($EnableBridge -and $EnableBuild) {
    Write-Section "Task 12: 生成 Flutter-Rust 桥接代码"

    # 检查工具
    $CargoList = cargo install --list
    if ($CargoList -notmatch "flutter_rust_bridge_codegen") {
        Write-Info "安装 flutter_rust_bridge_codegen..."
        cargo install flutter_rust_bridge_codegen --version 1.80.1 --features "uuid" --locked
    }

    if ($CargoList -notmatch "cargo-expand") {
        Write-Info "安装 cargo-expand..."
        cargo install cargo-expand --version 1.0.95 --locked
    }

    # 准备 Flutter 依赖
    Write-Info "获取 Flutter 依赖..."
    Push-Location flutter
    flutter pub get
    Pop-Location

    # 生成桥接代码
    Write-Info "生成桥接代码..."
    flutter_rust_bridge_codegen `
        --rust-input .\src\flutter_ffi.rs `
        --dart-output .\flutter\lib\generated_bridge.dart `
        --c-output .\flutter\macos\Runner\bridge_generated.h

    # 复制头文件
    Copy-Item .\flutter\macos\Runner\bridge_generated.h .\flutter\ios\Runner\bridge_generated.h -Force

    # 验证生成的文件
    if (Test-Path ".\flutter\lib\generated_bridge.dart") {
        Write-Success "桥接代码生成完成"
    } else {
        Write-Error "桥接代码生成失败"
        exit 1
    }
} else {
    Write-Warning "跳过桥接代码生成"
}

# Task 13: 构建 RustDeskTempTopMostWindow
if ($EnableTopmost -and $EnableBuild) {
    Write-Section "Task 13: 构建 RustDeskTempTopMostWindow"

    if (-not (Test-Path "temp\topmostwindow")) {
        New-Item -ItemType Directory -Path "temp\topmostwindow" -Force | Out-Null

        Write-Info "克隆 RustDeskTempTopMostWindow..."
        git clone https://github.com/rustdesk-org/RustDeskTempTopMostWindow.git temp\topmost_repo
        Push-Location temp\topmost_repo
        git checkout 53b548a5398624f7149a382000397993542ad796

        # 检测并升级项目工具集到 v143 (VS 2022)
        Write-Info "检查项目工具集版本..."
        $VcxprojPath = "WindowInjection\WindowInjection.vcxproj"
        $VcxprojContent = Get-Content $VcxprojPath -Raw

        if ($VcxprojContent -match '<PlatformToolset>v142</PlatformToolset>') {
            Write-Info "检测到 v142 工具集，升级到 v143 (VS 2022)..."
            $VcxprojContent = $VcxprojContent -replace '<PlatformToolset>v142</PlatformToolset>', '<PlatformToolset>v143</PlatformToolset>'
            Set-Content -Path $VcxprojPath -Value $VcxprojContent
            Write-Success "工具集已升级到 v143"
        }

        Write-Info "编译 WindowInjection.dll..."
        msbuild WindowInjection\WindowInjection.vcxproj `
            -p:Configuration=Release `
            -p:Platform=x64 `
            /p:TargetVersion=Windows10

        # 复制 DLL
        Copy-Item .\WindowInjection\x64\Release\WindowInjection.dll ..\temp\topmostwindow\ -Force

        Pop-Location
        Remove-Item -Recurse -Force temp\topmost_repo

        Write-Success "WindowInjection.dll 编译完成"
    } else {
        Write-Info "WindowInjection.dll 已存在,跳过编译"
    }
} else {
    Write-Warning "跳过 TopMostWindow 组件构建"
}

# Task 14: 构建 RustDesk 主程序
if ($EnableBuild) {
    Write-Section "Task 14: 构建 RustDesk 主程序"

    # 构建参数
    $BuildArgs = @("--portable", "--skip-portable-pack")
    if ($BuildFlutter) {
        $BuildArgs += "--flutter"
    }
    if ($BuildHwcodec) {
        $BuildArgs += "--hwcodec"
    }
    if ($BuildVram) {
        $BuildArgs += "--vram"
    }

    Write-Info "运行构建脚本: python build.py $($BuildArgs -join ' ')"
    python build.py @BuildArgs

    # 移动构建产物
    Write-Info "整理构建产物..."
    if (Test-Path "rustdesk") {
        Remove-Item -Recurse -Force rustdesk
    }
    Move-Item .\flutter\build\windows\x64\runner\Release .\rustdesk -Force

    # 验证构建
    if (Test-Path ".\rustdesk\rustdesk.exe") {
        $FileSize = (Get-Item .\rustdesk\rustdesk.exe).Length / 1MB
        Write-Success "主程序构建完成: rustdesk.exe ($([math]::Round($FileSize, 2)) MB)"
    } else {
        Write-Error "主程序构建失败"
        exit 1
    }
} else {
    Write-Section "Task 14: 跳过编译阶段"

    # 验证 rustdesk 目录是否存在
    if (-not (Test-Path ".\rustdesk\rustdesk.exe")) {
        Write-Error "rustdesk 目录不存在或缺少 rustdesk.exe，无法跳过编译。请先执行完整构建或手动准备 rustdesk 目录。"
        exit 1
    }

    $FileSize = (Get-Item .\rustdesk\rustdesk.exe).Length / 1MB
    Write-Info "使用现有主程序: rustdesk.exe ($([math]::Round($FileSize, 2)) MB)"
}

# Task 15-16: 集成驱动
if ($EnableDrivers) {
    Write-Section "Task 15: 集成 USB 虚拟显示器驱动"

    # 检查驱动是否已存在
    if (Test-Path ".\rustdesk\usbmmidd_v2") {
        Write-Info "USB 虚拟显示器驱动已存在，跳过下载和集成"
    } else {
        # 创建临时驱动目录
        New-Item -ItemType Directory -Path "temp\drivers" -Force | Out-Null

        Write-Info "下载 usbmmidd_v2 驱动..."
        $UsbDriverUrl = "https://github.com/rustdesk-org/rdev/releases/download/usbmmidd_v2/usbmmidd_v2.zip"
        $UsbDriverZip = "temp\drivers\usbmmidd_v2.zip"

        Invoke-WebRequest -Uri $UsbDriverUrl -OutFile $UsbDriverZip -UseBasicParsing

        Write-Info "解压驱动..."
        Expand-Archive -Path $UsbDriverZip -DestinationPath temp\drivers -Force

        Write-Info "清理不需要的文件..."
        Remove-Item -Recurse -Force temp\drivers\usbmmidd_v2\Win32 -ErrorAction SilentlyContinue
        Remove-Item -Force temp\drivers\usbmmidd_v2\deviceinstaller64.exe, temp\drivers\usbmmidd_v2\deviceinstaller.exe, temp\drivers\usbmmidd_v2\usbmmidd.bat -ErrorAction SilentlyContinue

        Write-Info "移动驱动到 rustdesk 目录..."
        Move-Item temp\drivers\usbmmidd_v2 .\rustdesk\ -Force

        Remove-Item $UsbDriverZip
        Write-Success "USB 虚拟显示器驱动已集成"
    }

    Write-Section "Task 16: 集成打印机驱动"

    # 检查打印机驱动是否已存在
    if ((Test-Path ".\rustdesk\drivers\RustDeskPrinterDriver") -and (Test-Path ".\rustdesk\printer_driver_adapter.dll")) {
        Write-Info "打印机驱动已存在，跳过下载和集成"
    } else {
        # 创建临时驱动目录
        New-Item -ItemType Directory -Path "temp\drivers" -Force | Out-Null

        Write-Info "下载打印机驱动文件..."
        $PrinterDriverUrl = "https://github.com/rustdesk/hbb_common/releases/download/driver/rustdesk_printer_driver_v4-1.4.zip"
        $PrinterAdapterUrl = "https://github.com/rustdesk/hbb_common/releases/download/driver/printer_driver_adapter.zip"
        $Sha256Url = "https://github.com/rustdesk/hbb_common/releases/download/driver/sha256sums"

        Invoke-WebRequest -Uri $PrinterDriverUrl -OutFile "temp\drivers\rustdesk_printer_driver_v4-1.4.zip" -UseBasicParsing
        Invoke-WebRequest -Uri $PrinterAdapterUrl -OutFile "temp\drivers\printer_driver_adapter.zip" -UseBasicParsing
        Invoke-WebRequest -Uri $Sha256Url -OutFile "temp\drivers\sha256sums" -UseBasicParsing

        Write-Info "验证 SHA256 校验和..."
        $ExpectedDriver = (Select-String -Path temp\drivers\sha256sums -Pattern '^([a-fA-F0-9]{64}) \*rustdesk_printer_driver_v4-1.4\.zip$').Matches.Groups[1].Value
        $ActualDriver = (Get-FileHash -Path temp\drivers\rustdesk_printer_driver_v4-1.4.zip -Algorithm SHA256).Hash

        $ExpectedAdapter = (Select-String -Path temp\drivers\sha256sums -Pattern '^([a-fA-F0-9]{64}) \*printer_driver_adapter\.zip$').Matches.Groups[1].Value
        $ActualAdapter = (Get-FileHash -Path temp\drivers\printer_driver_adapter.zip -Algorithm SHA256).Hash

        if ($ExpectedDriver -eq $ActualDriver -and $ExpectedAdapter -eq $ActualAdapter) {
            Write-Success "校验和验证通过"

            Write-Info "解压并安装打印机驱动..."
            Expand-Archive -Path temp\drivers\rustdesk_printer_driver_v4-1.4.zip -DestinationPath temp\drivers -Force
            New-Item -ItemType Directory -Path .\rustdesk\drivers -Force | Out-Null

            # 如果目标目录已存在，先删除
            if (Test-Path ".\rustdesk\drivers\RustDeskPrinterDriver") {
                Remove-Item -Recurse -Force ".\rustdesk\drivers\RustDeskPrinterDriver"
            }
            Move-Item temp\drivers\rustdesk_printer_driver_v4-1.4 .\rustdesk\drivers\RustDeskPrinterDriver -Force

            Expand-Archive -Path temp\drivers\printer_driver_adapter.zip -DestinationPath temp\drivers -Force
            Move-Item temp\drivers\printer_driver_adapter.dll .\rustdesk\ -Force

            Write-Success "打印机驱动已集成"
        } else {
            Write-Error "校验和验证失败,跳过打印机驱动安装"
            Write-Info "期望 Driver: $ExpectedDriver"
            Write-Info "实际 Driver: $ActualDriver"
            Write-Info "期望 Adapter: $ExpectedAdapter"
            Write-Info "实际 Adapter: $ActualAdapter"
        }

        # 清理临时文件
        Remove-Item temp\drivers\rustdesk_printer_driver_v4-1.4.zip, temp\drivers\printer_driver_adapter.zip, temp\drivers\sha256sums -ErrorAction SilentlyContinue
    }
} else {
    Write-Warning "跳过驱动集成"
}

# Task 17: 处理 Runner.res
Write-Section "Task 17: 处理 Runner.res"

$RunnerRes = Get-ChildItem -Path . -Filter "Runner.res" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($RunnerRes) {
    Write-Info "找到 Runner.res: $($RunnerRes.FullName)"
    New-Item -ItemType Directory -Path .\libs\portable -Force | Out-Null
    Copy-Item $RunnerRes.FullName .\libs\portable\Runner.res -Force
    Write-Success "Runner.res 已复制"
} else {
    Write-Warning "未找到 Runner.res 文件"
}

# Task 18: 集成 TopMostWindow 组件
if ($EnableTopmost) {
    Write-Section "Task 18: 集成 TopMostWindow 组件"

    if (Test-Path "temp\topmostwindow\WindowInjection.dll") {
        Copy-Item temp\topmostwindow\WindowInjection.dll .\rustdesk\ -Force
        Write-Success "WindowInjection.dll 已集成"

        # 清理临时目录
        Remove-Item -Recurse -Force temp\topmostwindow
    } else {
        Write-Warning "WindowInjection.dll 未找到"
    }
}

# Task 19: 构建自解压可执行文件
if ($EnablePortable) {
    Write-Section "Task 19: 构建自解压可执行文件"

    Write-Info "修改 manifest.xml..."
    $ManifestPath = "res\manifest.xml"
    (Get-Content $ManifestPath) | Where-Object { $_ -notmatch 'dpiAware' } | Set-Content $ManifestPath

    Write-Info "安装便携版打包器依赖..."
    Push-Location libs\portable
    pip install -r requirements.txt --quiet

    Write-Info "生成自解压打包器... (压缩级别: $($script:BROTLI_COMPRESSION_LEVEL))"
    python generate.py `
        -f ..\..\rustdesk\ `
        -o . `
        -e ..\..\rustdesk\rustdesk.exe `
        -l $script:BROTLI_COMPRESSION_LEVEL

    Pop-Location

    # 创建输出目录
    New-Item -ItemType Directory -Path SignOutput -Force | Out-Null

    # 移动生成的 EXE
    Write-Info "移动可执行文件..."
    Move-Item .\target\release\rustdesk-portable-packer.exe .\SignOutput\rustdesk-$($script:BUILD_VERSION)-x86_64.exe -Force

    $ExeSize = (Get-Item .\SignOutput\rustdesk-$($script:BUILD_VERSION)-x86_64.exe).Length / 1MB
    Write-Success "自解压可执行文件已生成: rustdesk-$($script:BUILD_VERSION)-x86_64.exe ($([math]::Round($ExeSize, 2)) MB)"
} else {
    Write-Warning "跳过 Portable 自解压程序生成"
}

# Task 20: 构建 MSI 安装包
if ($EnableMSI) {
    Write-Section "Task 20: 构建 MSI 安装包"

    Push-Location res\msi

    Write-Info "预处理 MSI 配置..."
    python preprocess.py --arp -d ..\..\rustdesk

    # 检查并升级 MSI 项目工具集
    Write-Info "检查 MSI 项目工具集..."
    $MsiProjects = Get-ChildItem -Path . -Filter "*.vcxproj" -Recurse
    foreach ($Project in $MsiProjects) {
        $ProjectContent = Get-Content $Project.FullName -Raw
        if ($ProjectContent -match '<PlatformToolset>v142</PlatformToolset>') {
            Write-Info "升级 $($Project.Name) 到 v143..."
            $ProjectContent = $ProjectContent -replace '<PlatformToolset>v142</PlatformToolset>', '<PlatformToolset>v143</PlatformToolset>'
            Set-Content -Path $Project.FullName -Value $ProjectContent
        }
    }

    Write-Info "恢复 NuGet 包..."
    # 检查 nuget.exe 是否存在，如果不存在则下载
    $NugetPath = ".\nuget.exe"
    if (-not (Test-Path $NugetPath)) {
        Write-Info "下载 NuGet.exe..."
        $NugetUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
        try {
            Invoke-WebRequest -Uri $NugetUrl -OutFile $NugetPath
            Write-Success "NuGet.exe 下载成功"
        } catch {
            Write-Error "下载 NuGet.exe 失败: $_"
            throw
        }
    }

    & $NugetPath restore msi.sln

    Write-Info "编译 MSI..."
    msbuild msi.sln `
        -p:Configuration=Release `
        -p:Platform=x64 `
        /p:TargetVersion=Windows10

    Write-Info "移动 MSI 文件..."
    Move-Item .\Package\bin\x64\Release\en-us\Package.msi ..\..\SignOutput\rustdesk-$($script:BUILD_VERSION)-x86_64.msi -Force

    Pop-Location

    $MsiSize = (Get-Item .\SignOutput\rustdesk-$($script:BUILD_VERSION)-x86_64.msi).Length / 1MB
    Write-Success "MSI 安装包已生成: rustdesk-$($script:BUILD_VERSION)-x86_64.msi ($([math]::Round($MsiSize, 2)) MB)"

    Write-Info "生成 SHA256 校验和..."
    Get-FileHash .\SignOutput\rustdesk-$($script:BUILD_VERSION)-x86_64.msi -Algorithm SHA256 | Format-List
} else {
    Write-Warning "跳过 MSI 安装包构建"
}

# 构建完成总结
Write-Section "构建完成"

Write-Success "RustDesk 构建成功完成!"
Write-Host ""
Write-Info "输出文件:"

if (Test-Path ".\SignOutput\rustdesk-$($script:BUILD_VERSION)-x86_64.exe") {
    $ExeSize = (Get-Item ".\SignOutput\rustdesk-$($script:BUILD_VERSION)-x86_64.exe").Length / 1MB
    Write-Host "  - rustdesk-$($script:BUILD_VERSION)-x86_64.exe ($([math]::Round($ExeSize, 2)) MB)"
}

if (Test-Path ".\SignOutput\rustdesk-$($script:BUILD_VERSION)-x86_64.msi") {
    $MsiSize = (Get-Item ".\SignOutput\rustdesk-$($script:BUILD_VERSION)-x86_64.msi").Length / 1MB
    Write-Host "  - rustdesk-$($script:BUILD_VERSION)-x86_64.msi ($([math]::Round($MsiSize, 2)) MB)"
}

Write-Host ""
Write-Info "输出目录: .\SignOutput\"
Write-Host ""

# 集成组件验证
Write-Info "集成组件验证:"
if (Test-Path ".\rustdesk\usbmmidd_v2") { Write-Host "  ✓ USB 虚拟显示器驱动" } else { Write-Host "  ✗ USB 虚拟显示器驱动" }
if (Test-Path ".\rustdesk\drivers\RustDeskPrinterDriver") { Write-Host "  ✓ 打印机驱动" } else { Write-Host "  ✗ 打印机驱动" }
if (Test-Path ".\rustdesk\printer_driver_adapter.dll") { Write-Host "  ✓ 打印机驱动适配器" } else { Write-Host "  ✗ 打印机驱动适配器" }
if (Test-Path ".\rustdesk\WindowInjection.dll") { Write-Host "  ✓ TopMostWindow 组件" } else { Write-Host "  ✗ TopMostWindow 组件" }
Write-Host ""

Write-Warning "注意事项:"
Write-Host "  - 构建的文件未签名,Windows SmartScreen 可能会警告"
Write-Host "  - 如需签名,请使用 res\job.py 或本地证书"
Write-Host "  - 测试前请确保关闭正在运行的 RustDesk 实例"
Write-Host ""

Write-Info "下一步:"
Write-Host "  1. 测试可执行文件: .\SignOutput\rustdesk-$($script:BUILD_VERSION)-x86_64.exe"
Write-Host "  2. 安装 MSI 包测试: .\SignOutput\rustdesk-$($script:BUILD_VERSION)-x86_64.msi"
Write-Host "  3. 查看构建日志排查问题"
Write-Host ""

Write-Success "构建脚本执行完毕!"
