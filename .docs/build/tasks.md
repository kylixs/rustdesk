# RustDesk Windows Flutter 本地构建任务清单

本文档提供了 RustDesk Windows Flutter 版本的本地构建任务清单，适用于手动构建环境。

---

## 环境准备阶段

### Task 1: 设置环境变量

- [ ] **Task 1.1**: 设置必要的环境变量
  ```powershell
  # 设置版本信息
  $env:VERSION = "1.4.3"
  $env:FLUTTER_VERSION = "3.24.5"
  $env:LLVM_VERSION = "15.0.6"
  $env:RUST_VERSION = "1.75"
  $env:VCPKG_COMMIT_ID = "120deac3062162151622ca4860575a33844ba10b"

  # 设置 vcpkg 配置
  $env:VCPKG_ROOT = "C:\vcpkg"
  $env:VCPKG_DEFAULT_HOST_TRIPLET = "x64-windows-static"

  # 设置构建输出目录
  $env:BUILD_OUTPUT = "$PWD\SignOutput"
  ```

### Task 2: 源代码准备

- [ ] **Task 2.1**: 克隆仓库及子模块
  ```bash
  git clone --recursive https://github.com/rustdesk/rustdesk.git
  cd rustdesk
  ```

  如果已克隆，更新子模块：
  ```bash
  git submodule update --init --recursive
  ```

---

## 工具链安装阶段

### Task 3: 安装 Visual Studio Build Tools

- [ ] **Task 3.1**: 下载并安装 Visual Studio 2022 Build Tools
  ```bash
  # 下载地址: https://visualstudio.microsoft.com/downloads/
  # 必需组件:
  # - MSVC v143 - VS 2022 C++ x64/x86 生成工具
  # - Windows 10/11 SDK
  # - C++ CMake 工具
  # - MSBuild
  # - NuGet 包管理器
  ```

- [ ] **Task 3.2**: 验证 MSBuild 安装
  ```powershell
  msbuild -version
  ```

### Task 4: 安装 LLVM 和 Clang

- [ ] **Task 4.1**: 下载并安装 LLVM 15.0.6
  ```powershell
  # 方法1: 使用 Chocolatey
  choco install llvm --version=15.0.6 -y

  # 方法2: 手动下载
  # https://github.com/llvm/llvm-project/releases/tag/llvmorg-15.0.6
  ```

- [ ] **Task 4.2**: 验证 LLVM 安装
  ```powershell
  clang --version
  ```

### Task 5: 安装 Rust 工具链

- [ ] **Task 5.1**: 安装 Rustup
  ```powershell
  # 下载并运行安装器
  # https://rustup.rs/
  Invoke-WebRequest -Uri https://win.rustup.rs/x86_64 -OutFile rustup-init.exe
  .\rustup-init.exe -y
  ```

- [ ] **Task 5.2**: 配置 Rust 工具链
  ```powershell
  # 安装指定版本的工具链
  rustup toolchain install 1.75-x86_64-pc-windows-msvc
  rustup default 1.75-x86_64-pc-windows-msvc

  # 添加目标平台
  rustup target add x86_64-pc-windows-msvc

  # 添加必需组件
  rustup component add rustfmt
  ```

- [ ] **Task 5.3**: 验证 Rust 安装
  ```powershell
  rustc --version
  cargo --version
  ```

### Task 6: 安装 Flutter SDK

- [ ] **Task 6.1**: 下载 Flutter 3.24.5
  ```powershell
  # 下载 Flutter SDK
  Invoke-WebRequest -Uri https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.24.5-stable.zip -OutFile flutter.zip

  # 解压到目标目录
  Expand-Archive -Path flutter.zip -DestinationPath C:\
  ```

- [ ] **Task 6.2**: 配置 Flutter 环境变量
  ```powershell
  # 添加到 PATH
  $env:Path += ";C:\flutter\bin"
  [Environment]::SetEnvironmentVariable("Path", $env:Path, [EnvironmentVariableTarget]::User)
  ```

- [ ] **Task 6.3**: 验证并配置 Flutter
  ```powershell
  flutter doctor -v
  flutter config --enable-windows-desktop
  flutter precache --windows
  ```

### Task 7: 替换 RustDesk 自定义 Flutter 引擎

- [ ] **Task 7.1**: 下载自定义引擎
  ```powershell
  Invoke-WebRequest -Uri https://github.com/rustdesk/engine/releases/download/main/windows-x64-release.zip -OutFile windows-x64-release.zip
  ```

- [ ] **Task 7.2**: 解压并替换引擎
  ```powershell
  # 解压引擎文件
  Expand-Archive -Path windows-x64-release.zip -DestinationPath windows-x64-release -Force

  # 查找 Flutter 引擎路径
  $flutterPath = (Get-Command flutter).Source | Split-Path | Split-Path
  $enginePath = "$flutterPath\bin\cache\artifacts\engine\windows-x64-release"

  # 备份原引擎（可选）
  if (Test-Path $enginePath) {
    Move-Item $enginePath "$enginePath.backup" -Force
  }

  # 替换引擎
  Copy-Item -Path "windows-x64-release\*" -Destination $enginePath -Recurse -Force
  ```

- [ ] **Task 7.3**: 清理临时文件
  ```powershell
  Remove-Item windows-x64-release.zip
  Remove-Item -Recurse windows-x64-release
  ```

### Task 8: 应用 Flutter 补丁

- [ ] **Task 8.1**: 应用补丁（仅 Flutter 3.24.5）
  ```powershell
  # 复制补丁文件到 Flutter 目录
  $flutterPath = (Get-Command flutter).Source | Split-Path | Split-Path
  Copy-Item .github\patches\flutter_3.24.4_dropdown_menu_enableFilter.diff $flutterPath

  # 应用补丁
  cd $flutterPath
  git apply flutter_3.24.4_dropdown_menu_enableFilter.diff
  cd -
  ```

### Task 9: 配置 vcpkg

- [ ] **Task 9.1**: 克隆 vcpkg
  ```powershell
  # 克隆到指定位置
  git clone https://github.com/Microsoft/vcpkg.git C:\vcpkg
  cd C:\vcpkg

  # 切换到指定提交
  git checkout 120deac3062162151622ca4860575a33844ba10b
  ```

- [ ] **Task 9.2**: 引导 vcpkg
  ```powershell
  cd C:\vcpkg
  .\bootstrap-vcpkg.bat
  ```

- [ ] **Task 9.3**: 设置环境变量
  ```powershell
  $env:VCPKG_ROOT = "C:\vcpkg"
  [Environment]::SetEnvironmentVariable("VCPKG_ROOT", "C:\vcpkg", [EnvironmentVariableTarget]::User)
  ```

### Task 10: 安装 vcpkg 依赖包

- [ ] **Task 10.1**: 安装 C++ 依赖库
  ```powershell
  cd C:\vcpkg

  # 安装依赖包（根据 vcpkg.json）
  .\vcpkg.exe install --triplet x64-windows-static
  ```

  依赖包列表（从项目根目录的 vcpkg.json 读取）:
  - libvpx
  - libyuv
  - opus
  - aom
  - 其他项目依赖

- [ ] **Task 10.2**: 验证安装
  ```powershell
  # 检查已安装的包
  .\vcpkg.exe list

  # 如果有失败，查看日志
  Get-ChildItem C:\vcpkg\buildtrees\*\*.log
  ```

### Task 11: 安装 Python 和依赖

- [ ] **Task 11.1**: 安装 Python 3
  ```powershell
  # 方法1: 使用 Chocolatey
  choco install python -y

  # 方法2: 从官网下载
  # https://www.python.org/downloads/
  ```

- [ ] **Task 11.2**: 安装 Python 包
  ```powershell
  # 升级 pip
  python -m pip install --upgrade pip

  # 安装构建所需的包
  pip3 install requests argparse
  ```

---

## 前置依赖构建阶段

### Task 12: 生成 Flutter-Rust 桥接代码

- [ ] **Task 12.1**: 安装 flutter_rust_bridge 工具
  ```powershell
  # 安装 cargo-expand
  cargo install cargo-expand --version 1.0.95 --locked

  # 安装 flutter_rust_bridge_codegen
  cargo install flutter_rust_bridge_codegen --version 1.80.1 --features "uuid" --locked
  ```

- [ ] **Task 12.2**: 准备 Flutter 依赖
  ```powershell
  cd flutter

  # 修改 pubspec.yaml（如需要）
  # 将 extended_text: 14.0.0 替换为 extended_text: 13.0.0

  # 获取 Flutter 依赖
  flutter pub get
  cd ..
  ```

- [ ] **Task 12.3**: 生成桥接代码
  ```powershell
  # 运行代码生成器
  flutter_rust_bridge_codegen `
    --rust-input .\src\flutter_ffi.rs `
    --dart-output .\flutter\lib\generated_bridge.dart `
    --c-output .\flutter\macos\Runner\bridge_generated.h

  # 复制头文件到 iOS
  Copy-Item .\flutter\macos\Runner\bridge_generated.h .\flutter\ios\Runner\bridge_generated.h
  ```

- [ ] **Task 12.4**: 验证生成的文件
  ```powershell
  # 检查生成的文件是否存在
  Test-Path .\src\bridge_generated.rs
  Test-Path .\src\bridge_generated.io.rs
  Test-Path .\flutter\lib\generated_bridge.dart
  Test-Path .\flutter\lib\generated_bridge.freezed.dart
  Test-Path .\flutter\macos\Runner\bridge_generated.h
  Test-Path .\flutter\ios\Runner\bridge_generated.h
  ```

### Task 13: 构建 RustDeskTempTopMostWindow

- [ ] **Task 13.1**: 克隆 TopMostWindow 项目
  ```powershell
  # 克隆到临时目录
  git clone https://github.com/rustdesk-org/RustDeskTempTopMostWindow.git RustDeskTempTopMostWindow
  cd RustDeskTempTopMostWindow

  # 切换到特定提交 (v0.3)
  git checkout 53b548a5398624f7149a382000397993542ad796
  ```

- [ ] **Task 13.2**: 编译 WindowInjection.dll
  ```powershell
  # 使用 MSBuild 编译
  msbuild WindowInjection\WindowInjection.vcxproj `
    -p:Configuration=Release `
    -p:Platform=x64 `
    /p:TargetVersion=Windows10
  ```

- [ ] **Task 13.3**: 复制编译产物
  ```powershell
  # 返回 rustdesk 目录
  cd ..

  # 创建临时目录保存 dll
  mkdir -p temp_topmostwindow
  Copy-Item RustDeskTempTopMostWindow\WindowInjection\x64\Release\WindowInjection.dll temp_topmostwindow\
  ```

- [ ] **Task 13.4**: 清理临时项目（可选）
  ```powershell
  Remove-Item -Recurse -Force RustDeskTempTopMostWindow
  ```

---

## 核心构建阶段

### Task 14: 构建 RustDesk 主程序

- [ ] **Task 14.1**: 运行构建脚本
  ```powershell
  # 确保在项目根目录
  cd <rustdesk-root>

  # 运行构建
  python .\build.py --portable --hwcodec --flutter --vram --skip-portable-pack
  ```

  构建参数说明：
  - `--portable`: 构建便携版
  - `--hwcodec`: 启用硬件编解码支持
  - `--flutter`: 使用 Flutter UI
  - `--vram`: 启用 VRAM 优化（Windows 独有）
  - `--skip-portable-pack`: 跳过便携版打包（稍后手动打包）

- [ ] **Task 14.2**: 移动构建产物
  ```powershell
  # 创建 rustdesk 输出目录
  if (Test-Path rustdesk) {
    Remove-Item -Recurse -Force rustdesk
  }

  # 移动 Flutter 构建输出
  Move-Item .\flutter\build\windows\x64\runner\Release .\rustdesk
  ```

- [ ] **Task 14.3**: 验证构建
  ```powershell
  # 检查主程序是否存在
  Test-Path .\rustdesk\rustdesk.exe

  # 查看文件大小
  Get-Item .\rustdesk\rustdesk.exe | Select-Object Name, Length
  ```

### Task 15: 集成 USB 虚拟显示器驱动

- [ ] **Task 15.1**: 下载 usbmmidd_v2 驱动
  ```powershell
  Invoke-WebRequest -Uri https://github.com/rustdesk-org/rdev/releases/download/usbmmidd_v2/usbmmidd_v2.zip -OutFile usbmmidd_v2.zip
  ```

- [ ] **Task 15.2**: 解压驱动文件
  ```powershell
  Expand-Archive usbmmidd_v2.zip -DestinationPath . -Force
  ```

- [ ] **Task 15.3**: 清理不需要的文件
  ```powershell
  # 删除 32 位驱动
  Remove-Item -Path usbmmidd_v2\Win32 -Recurse -Force

  # 删除不需要的安装工具
  Remove-Item -Path usbmmidd_v2\deviceinstaller64.exe -Force
  Remove-Item -Path usbmmidd_v2\deviceinstaller.exe -Force
  Remove-Item -Path usbmmidd_v2\usbmmidd.bat -Force
  ```

- [ ] **Task 15.4**: 移动到 rustdesk 目录
  ```powershell
  Move-Item .\usbmmidd_v2 .\rustdesk\ -Force
  ```

- [ ] **Task 15.5**: 清理临时文件
  ```powershell
  Remove-Item usbmmidd_v2.zip
  ```

### Task 16: 集成打印机驱动

- [ ] **Task 16.1**: 下载打印机驱动文件
  ```powershell
  Invoke-WebRequest -Uri https://github.com/rustdesk/hbb_common/releases/download/driver/rustdesk_printer_driver_v4-1.4.zip -OutFile rustdesk_printer_driver_v4-1.4.zip
  Invoke-WebRequest -Uri https://github.com/rustdesk/hbb_common/releases/download/driver/printer_driver_adapter.zip -OutFile printer_driver_adapter.zip
  Invoke-WebRequest -Uri https://github.com/rustdesk/hbb_common/releases/download/driver/sha256sums -OutFile sha256sums
  ```

- [ ] **Task 16.2**: 验证 SHA256 校验和
  ```powershell
  # 提取驱动的 SHA256 校验和
  $checksum_driver = (Select-String -Path .\sha256sums -Pattern '^([a-fA-F0-9]{64}) \*rustdesk_printer_driver_v4-1.4\.zip$').Matches.Groups[1].Value
  $downloadsum_driver = (Get-FileHash -Path rustdesk_printer_driver_v4-1.4.zip -Algorithm SHA256).Hash

  # 提取适配器的 SHA256 校验和
  $checksum_adapter = (Select-String -Path .\sha256sums -Pattern '^([a-fA-F0-9]{64}) \*printer_driver_adapter\.zip$').Matches.Groups[1].Value
  $downloadsum_adapter = (Get-FileHash -Path printer_driver_adapter.zip -Algorithm SHA256).Hash

  # 输出比对结果
  Write-Host "Driver checksum match: $($checksum_driver -eq $downloadsum_driver)"
  Write-Host "Adapter checksum match: $($checksum_adapter -eq $downloadsum_adapter)"
  ```

- [ ] **Task 16.3**: 解压并移动驱动（仅在校验通过时）
  ```powershell
  if ($checksum_driver -eq $downloadsum_driver -and $checksum_adapter -eq $downloadsum_adapter) {
    Write-Host "Checksums match, extracting files..."

    # 解压驱动
    Expand-Archive rustdesk_printer_driver_v4-1.4.zip -DestinationPath . -Force
    New-Item -ItemType Directory -Path .\rustdesk\drivers -Force
    Move-Item .\rustdesk_printer_driver_v4-1.4 .\rustdesk\drivers\RustDeskPrinterDriver -Force

    # 解压适配器
    Expand-Archive printer_driver_adapter.zip -DestinationPath . -Force
    Move-Item .\printer_driver_adapter.dll .\rustdesk\ -Force

    Write-Host "Printer driver installed successfully."
  } else {
    Write-Warning "Checksum verification failed! Skipping printer driver installation."
  }
  ```

- [ ] **Task 16.4**: 清理临时文件
  ```powershell
  Remove-Item rustdesk_printer_driver_v4-1.4.zip -ErrorAction SilentlyContinue
  Remove-Item printer_driver_adapter.zip -ErrorAction SilentlyContinue
  Remove-Item sha256sums -ErrorAction SilentlyContinue
  ```

### Task 17: 处理 Runner.res

- [ ] **Task 17.1**: 查找 Runner.res 文件
  ```powershell
  # 在构建目录中查找
  $runnerRes = Get-ChildItem -Path . -Filter "Runner.res" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

  if ($runnerRes) {
    Write-Host "Found Runner.res at: $($runnerRes.FullName)"
  } else {
    Write-Warning "Runner.res not found"
  }
  ```

- [ ] **Task 17.2**: 复制到便携版目录
  ```powershell
  if ($runnerRes) {
    # 确保目标目录存在
    New-Item -ItemType Directory -Path .\libs\portable -Force

    # 复制文件
    Copy-Item $runnerRes.FullName .\libs\portable\Runner.res -Force

    # 验证
    Get-Item .\libs\portable\Runner.res | Select-Object Name, Length
  }
  ```

  **说明**: Runner.res 由 `.\flutter\windows\runner\Runner.rc` 编译而来，包含实际的版本信息

### Task 18: 集成 TopMostWindow 组件

- [ ] **Task 18.1**: 复制 WindowInjection.dll
  ```powershell
  # 从之前构建的临时目录复制
  if (Test-Path temp_topmostwindow\WindowInjection.dll) {
    Copy-Item temp_topmostwindow\WindowInjection.dll .\rustdesk\ -Force
    Write-Host "WindowInjection.dll integrated successfully."
  } else {
    Write-Warning "WindowInjection.dll not found in temp directory"
  }
  ```

- [ ] **Task 18.2**: 清理临时目录
  ```powershell
  Remove-Item -Recurse -Force temp_topmostwindow -ErrorAction SilentlyContinue
  ```

---

## 打包与签名阶段

### Task 19: 构建自解压可执行文件

- [ ] **Task 19.1**: 修改 manifest.xml
  ```powershell
  # 使用 PowerShell 移除 dpiAware 行
  $manifestPath = "res\manifest.xml"
  (Get-Content $manifestPath) | Where-Object { $_ -notmatch 'dpiAware' } | Set-Content $manifestPath
  ```

- [ ] **Task 19.2**: 安装便携版打包器依赖
  ```powershell
  cd libs\portable
  pip3 install -r requirements.txt
  cd ..\..
  ```

- [ ] **Task 19.3**: 生成自解压打包器
  ```powershell
  cd libs\portable

  python .\generate.py `
    -f ..\..\rustdesk\ `
    -o . `
    -e ..\..\rustdesk\rustdesk.exe

  cd ..\..
  ```

- [ ] **Task 19.4**: 移动生成的 EXE
  ```powershell
  # 创建输出目录
  New-Item -ItemType Directory -Path SignOutput -Force

  # 移动可执行文件
  Move-Item .\target\release\rustdesk-portable-packer.exe .\SignOutput\rustdesk-$env:VERSION-x86_64.exe -Force
  ```

- [ ] **Task 19.5**: 验证 EXE
  ```powershell
  Get-Item .\SignOutput\rustdesk-$env:VERSION-x86_64.exe | Select-Object Name, Length
  ```

### Task 20: 构建 MSI 安装包

- [ ] **Task 20.1**: 预处理 MSI 配置
  ```powershell
  cd res\msi
  python preprocess.py --arp -d ..\..\rustdesk
  ```

  参数说明：
  - `--arp`: 添加到"添加/删除程序"
  - `-d ..\..\rustdesk`: 指定源文件目录

- [ ] **Task 20.2**: 恢复 NuGet 包
  ```powershell
  nuget restore msi.sln
  ```

- [ ] **Task 20.3**: 编译 MSI
  ```powershell
  msbuild msi.sln `
    -p:Configuration=Release `
    -p:Platform=x64 `
    /p:TargetVersion=Windows10
  ```

- [ ] **Task 20.4**: 移动 MSI 文件
  ```powershell
  Move-Item .\Package\bin\x64\Release\en-us\Package.msi ..\..\SignOutput\rustdesk-$env:VERSION-x86_64.msi -Force
  cd ..\..
  ```

- [ ] **Task 20.5**: 生成校验和
  ```powershell
  # 计算 SHA256
  Get-FileHash .\SignOutput\rustdesk-$env:VERSION-x86_64.msi -Algorithm SHA256 | Format-List

  # 或使用 sha256sum（如果已安装 Git Bash）
  # sha256sum .\SignOutput\rustdesk-*.msi
  ```

### Task 21: 代码签名（可选）

- [ ] **Task 21.1**: 签名 rustdesk 目录文件（可选）
  ```powershell
  # 方法1: 使用项目签名服务（需要配置）
  $env:BASE_URL = "<sign-service-url>"
  $env:SECRET_KEY = "<sign-secret-key>"
  python res\job.py sign_files .\rustdesk\
  ```

  ```powershell
  # 方法2: 使用本地证书签名
  # 需要有效的代码签名证书
  $cert = Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert | Select-Object -First 1

  Get-ChildItem .\rustdesk\*.exe, .\rustdesk\*.dll -Recurse | ForEach-Object {
    Set-AuthenticodeSignature -FilePath $_.FullName -Certificate $cert -TimestampServer "http://timestamp.digicert.com"
  }
  ```

- [ ] **Task 21.2**: 签名最终产物（可选）
  ```powershell
  # 方法1: 使用项目签名服务
  python res\job.py sign_files .\SignOutput
  ```

  ```powershell
  # 方法2: 使用本地证书
  $cert = Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert | Select-Object -First 1

  Set-AuthenticodeSignature -FilePath .\SignOutput\rustdesk-$env:VERSION-x86_64.exe -Certificate $cert -TimestampServer "http://timestamp.digicert.com"
  Set-AuthenticodeSignature -FilePath .\SignOutput\rustdesk-$env:VERSION-x86_64.msi -Certificate $cert -TimestampServer "http://timestamp.digicert.com"
  ```

---

## 验证阶段

### Task 22: 构建验证

- [ ] **Task 22.1**: 验证 EXE 文件
  ```powershell
  # 检查文件存在和大小
  $exeFile = Get-Item .\SignOutput\rustdesk-$env:VERSION-x86_64.exe
  Write-Host "EXE File: $($exeFile.Name)"
  Write-Host "Size: $([math]::Round($exeFile.Length / 1MB, 2)) MB"

  # 检查文件签名（如果已签名）
  Get-AuthenticodeSignature .\SignOutput\rustdesk-$env:VERSION-x86_64.exe | Format-List
  ```

- [ ] **Task 22.2**: 验证 MSI 文件
  ```powershell
  # 检查文件存在和大小
  $msiFile = Get-Item .\SignOutput\rustdesk-$env:VERSION-x86_64.msi
  Write-Host "MSI File: $($msiFile.Name)"
  Write-Host "Size: $([math]::Round($msiFile.Length / 1MB, 2)) MB"

  # 检查文件签名（如果已签名）
  Get-AuthenticodeSignature .\SignOutput\rustdesk-$env:VERSION-x86_64.msi | Format-List
  ```

- [ ] **Task 22.3**: 功能测试
  ```powershell
  # 测试 EXE 是否可运行
  .\SignOutput\rustdesk-$env:VERSION-x86_64.exe --version

  # 或直接运行查看 UI
  # Start-Process .\SignOutput\rustdesk-$env:VERSION-x86_64.exe
  ```

- [ ] **Task 22.4**: 验证集成组件
  ```powershell
  # 检查驱动文件是否存在
  Test-Path .\rustdesk\usbmmidd_v2
  Test-Path .\rustdesk\drivers\RustDeskPrinterDriver
  Test-Path .\rustdesk\printer_driver_adapter.dll
  Test-Path .\rustdesk\WindowInjection.dll
  ```

---

## 清理阶段

### Task 23: 清理构建产物（可选）

- [ ] **Task 23.1**: 清理临时下载文件
  ```powershell
  # 清理引擎和驱动下载文件
  Remove-Item windows-x64-release.zip -ErrorAction SilentlyContinue
  Remove-Item -Recurse windows-x64-release -ErrorAction SilentlyContinue
  Remove-Item usbmmidd_v2.zip -ErrorAction SilentlyContinue
  Remove-Item rustdesk_printer_driver_v4-1.4.zip -ErrorAction SilentlyContinue
  Remove-Item printer_driver_adapter.zip -ErrorAction SilentlyContinue
  Remove-Item sha256sums -ErrorAction SilentlyContinue
  ```

- [ ] **Task 23.2**: 清理中间构建目录（可选）
  ```powershell
  # 保留 SignOutput，清理其他
  Remove-Item -Recurse rustdesk -ErrorAction SilentlyContinue
  ```

- [ ] **Task 23.3**: 清理 Rust 构建缓存（节省空间）
  ```powershell
  cargo clean
  ```

- [ ] **Task 23.4**: 清理 Flutter 构建缓存（节省空间）
  ```powershell
  cd flutter
  flutter clean
  cd ..
  ```

---

## 任务总结

### 必需任务

核心构建流程包括：
1. **环境准备** (Task 1-2)
2. **工具链安装** (Task 3-11)
3. **前置依赖构建** (Task 12-13)
4. **主程序构建** (Task 14)
5. **最终打包** (Task 19-20)

### 可选任务

增强功能和优化：
- **Task 15-16**: USB 驱动和打印机驱动集成（增强功能）
- **Task 17**: Runner.res 处理（版本信息完整性）
- **Task 18**: TopMostWindow 组件（窗口管理增强）
- **Task 21**: 代码签名（发布版本建议）
- **Task 22**: 验证测试（质量保证）
- **Task 23**: 清理工作（节省空间）

### 关键检查点

1. ✅ **工具链完整**: MSVC, LLVM, Rust, Flutter, vcpkg 均已安装
2. ✅ **Flutter 引擎已替换**: 使用 RustDesk 自定义引擎
3. ✅ **桥接代码已生成**: bridge_generated 文件存在
4. ✅ **TopMostWindow 已构建**: WindowInjection.dll 存在
5. ✅ **主程序构建成功**: rustdesk.exe 可执行
6. ✅ **驱动已集成**: USB 驱动和打印机驱动就位
7. ✅ **打包完成**: EXE 和 MSI 文件生成
8. ✅ **签名完成**: 文件已签名（如需要）
9. ✅ **功能验证通过**: 程序可正常运行

### 预计构建时间

- 首次构建（包含依赖安装）: **2-4 小时**
- 后续构建（依赖已缓存）: **30-60 分钟**

### 磁盘空间需求

- vcpkg 依赖: ~5-10 GB
- Flutter SDK: ~3 GB
- Rust 工具链: ~2 GB
- 构建产物: ~500 MB - 1 GB
- **总计**: 约 **15-20 GB**

---

## 常见问题

### Q1: vcpkg 安装依赖失败
**A**:
- 检查网络连接，某些包需要从 GitHub 下载
- 查看 `C:\vcpkg\buildtrees\` 下的详细日志
- 确保有足够的磁盘空间（至少 10 GB）

### Q2: Flutter 引擎替换后仍有问题
**A**:
- 运行 `flutter doctor -v` 检查状态
- 确认引擎路径正确
- 尝试 `flutter clean` 后重新构建

### Q3: MSI 构建失败
**A**:
- 确认已安装 Visual Studio Build Tools
- 检查 NuGet 是否正确安装: `nuget help`
- 查看 MSBuild 版本: `msbuild -version`

### Q4: 桥接代码生成失败
**A**:
- 确认 `flutter_rust_bridge_codegen` 已正确安装
- 检查 Rust 和 Flutter 版本是否匹配
- 清理后重试: `cargo clean && flutter clean`

### Q5: TopMostWindow 编译失败
**A**:
- 确认已安装 C++ 桌面开发工作负载
- 检查 Windows SDK 版本
- 确认项目文件路径正确

### Q6: 签名失败
**A**:
- 本地签名需要有效的代码签名证书
- 远程签名需要配置 `BASE_URL` 和 `SECRET_KEY`
- 可跳过签名，但 Windows SmartScreen 可能会警告

---

## 附录: 完整构建脚本示例

```powershell
# build-rustdesk-windows.ps1
# RustDesk Windows Flutter 完整构建脚本

# 设置错误处理
$ErrorActionPreference = "Stop"

# 设置环境变量
$env:VERSION = "1.4.3"
$env:VCPKG_ROOT = "C:\vcpkg"
$env:VCPKG_DEFAULT_HOST_TRIPLET = "x64-windows-static"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "RustDesk Windows Flutter Build Script" -ForegroundColor Cyan
Write-Host "Version: $env:VERSION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Task 12: 生成桥接代码
Write-Host "`n[Task 12] Generating Flutter-Rust bridge..." -ForegroundColor Yellow
flutter_rust_bridge_codegen `
  --rust-input .\src\flutter_ffi.rs `
  --dart-output .\flutter\lib\generated_bridge.dart `
  --c-output .\flutter\macos\Runner\bridge_generated.h
Copy-Item .\flutter\macos\Runner\bridge_generated.h .\flutter\ios\Runner\bridge_generated.h

# Task 13: 构建 TopMostWindow
Write-Host "`n[Task 13] Building RustDeskTempTopMostWindow..." -ForegroundColor Yellow
git clone https://github.com/rustdesk-org/RustDeskTempTopMostWindow.git temp_topmost
cd temp_topmost
git checkout 53b548a5398624f7149a382000397993542ad796
msbuild WindowInjection\WindowInjection.vcxproj -p:Configuration=Release -p:Platform=x64 /p:TargetVersion=Windows10
cd ..
mkdir temp_topmostwindow -Force
Copy-Item temp_topmost\WindowInjection\x64\Release\WindowInjection.dll temp_topmostwindow\
Remove-Item -Recurse -Force temp_topmost

# Task 14: 构建主程序
Write-Host "`n[Task 14] Building RustDesk main program..." -ForegroundColor Yellow
python .\build.py --portable --hwcodec --flutter --vram --skip-portable-pack
Move-Item .\flutter\build\windows\x64\runner\Release .\rustdesk -Force

# Task 15: 集成 USB 驱动
Write-Host "`n[Task 15] Integrating USB virtual display driver..." -ForegroundColor Yellow
Invoke-WebRequest -Uri https://github.com/rustdesk-org/rdev/releases/download/usbmmidd_v2/usbmmidd_v2.zip -OutFile usbmmidd_v2.zip
Expand-Archive usbmmidd_v2.zip -Force
Remove-Item usbmmidd_v2\Win32 -Recurse -Force
Remove-Item usbmmidd_v2\deviceinstaller*.exe, usbmmidd_v2\usbmmidd.bat -Force
Move-Item usbmmidd_v2 .\rustdesk\ -Force
Remove-Item usbmmidd_v2.zip

# Task 16: 集成打印机驱动
Write-Host "`n[Task 16] Integrating printer driver..." -ForegroundColor Yellow
# ... (完整脚本请参考各任务步骤)

# Task 17: 处理 Runner.res
Write-Host "`n[Task 17] Processing Runner.res..." -ForegroundColor Yellow
$runnerRes = Get-ChildItem -Path . -Filter "Runner.res" -Recurse | Select-Object -First 1
if ($runnerRes) {
  Copy-Item $runnerRes.FullName .\libs\portable\Runner.res -Force
}

# Task 18: 集成 TopMostWindow
Write-Host "`n[Task 18] Integrating TopMostWindow component..." -ForegroundColor Yellow
Copy-Item temp_topmostwindow\WindowInjection.dll .\rustdesk\ -Force

# Task 19: 构建自解压 EXE
Write-Host "`n[Task 19] Building self-extracting executable..." -ForegroundColor Yellow
cd libs\portable
pip3 install -r requirements.txt
python .\generate.py -f ..\..\rustdesk\ -o . -e ..\..\rustdesk\rustdesk.exe
cd ..\..
New-Item -ItemType Directory -Path SignOutput -Force
Move-Item .\target\release\rustdesk-portable-packer.exe .\SignOutput\rustdesk-$env:VERSION-x86_64.exe -Force

# Task 20: 构建 MSI
Write-Host "`n[Task 20] Building MSI installer..." -ForegroundColor Yellow
cd res\msi
python preprocess.py --arp -d ..\..\rustdesk
nuget restore msi.sln
msbuild msi.sln -p:Configuration=Release -p:Platform=x64 /p:TargetVersion=Windows10
Move-Item .\Package\bin\x64\Release\en-us\Package.msi ..\..\SignOutput\rustdesk-$env:VERSION-x86_64.msi -Force
cd ..\..

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Build completed successfully!" -ForegroundColor Green
Write-Host "Output files:" -ForegroundColor Green
Get-ChildItem .\SignOutput\rustdesk-* | ForEach-Object {
  Write-Host "  - $($_.Name) ($([math]::Round($_.Length / 1MB, 2)) MB)" -ForegroundColor Green
}
Write-Host "========================================" -ForegroundColor Green
```

---

**文档版本**: 2.0
**更新日期**: 2025-10-18
**对应构建文档**: Windows_Flutter_Build_Steps.md
**变更**: 移除 GitHub Actions 特有任务，替换为本地构建操作
