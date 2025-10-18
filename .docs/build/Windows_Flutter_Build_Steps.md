# RustDesk Windows Flutter 构建步骤详细文档

本文档详细记录了 RustDesk 项目在 GitHub Actions 中 Windows Flutter 版本的完整构建流程。

## 构建环境配置

- **操作系统**: Windows Server 2022
- **目标平台**: x86_64-pc-windows-msvc
- **架构**: x86_64
- **vcpkg triplet**: x64-windows-static

## 前置依赖任务

1. `build-RustDeskTempTopMostWindow` - 构建 TopMost 窗口组件
2. `generate-bridge` - 生成 Rust-Flutter 桥接代码

---

## 详细构建步骤

### 步骤 1: 导出 GitHub Actions 缓存环境变量

```javascript
// 使用 actions/github-script@v6
core.exportVariable('ACTIONS_CACHE_URL', process.env.ACTIONS_CACHE_URL || '');
core.exportVariable('ACTIONS_RUNTIME_TOKEN', process.env.ACTIONS_RUNTIME_TOKEN || '');
```

### 步骤 2: 检出源代码

```bash
# 使用 actions/checkout@v4
git clone --recursive <repository>
```

**参数**:
- `submodules: recursive` - 递归克隆所有子模块

### 步骤 3: 恢复 Bridge 文件

```bash
# 使用 actions/download-artifact@master
# 下载 artifact: bridge-artifact
# 目标路径: ./
```

### 步骤 4: 安装 LLVM 和 Clang

```bash
# 使用 KyleMayes/install-llvm-action@v1
# 版本: ${{ env.LLVM_VERSION }}
```

### 步骤 5: 安装 Flutter

```bash
# 使用 subosito/flutter-action@v2.12.0
# channel: stable
# flutter-version: ${{ env.FLUTTER_VERSION }}
```

### 步骤 6: 替换为 RustDesk 自定义 Flutter 引擎

```powershell
# 检查 Flutter 安装
flutter doctor -v

# 预缓存 Windows 平台文件
flutter precache --windows

# 下载自定义引擎
Invoke-WebRequest -Uri https://github.com/rustdesk/engine/releases/download/main/windows-x64-release.zip -OutFile windows-x64-release.zip

# 解压
Expand-Archive -Path windows-x64-release.zip -DestinationPath windows-x64-release

# 替换官方引擎
mv -Force windows-x64-release/* C:/hostedtoolcache/windows/flutter/stable-${{ env.FLUTTER_VERSION }}-x64/bin/cache/artifacts/engine/windows-x64-release/
```

**说明**: 修复 Flutter issue #155685

### 步骤 7: 打补丁到 Flutter

```bash
# 复制补丁文件
cp .github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff $(dirname $(dirname $(which flutter)))

# 进入 Flutter 安装目录
cd $(dirname $(dirname $(which flutter)))

# 应用补丁 (仅针对 Flutter 3.24.5)
[[ "3.24.5" == ${{ env.FLUTTER_VERSION }} ]] && git apply flutter_3.24.4_dropdown_menu_enableFilter.diff
```

### 步骤 8: 安装 Rust 工具链

```bash
# 使用 dtolnay/rust-toolchain@v1
# toolchain: ${{ env.SCITER_RUST_VERSION }}
# targets: x86_64-pc-windows-msvc
# components: rustfmt
```

### 步骤 9: 配置 Rust 缓存

```bash
# 使用 Swatinem/rust-cache@v2
# prefix-key: windows-2022
```

### 步骤 10: 设置 vcpkg 和 GitHub Actions 二进制缓存

```bash
# 使用 lukka/run-vcpkg@v11
# vcpkgDirectory: C:\vcpkg
# vcpkgGitCommitId: ${{ env.VCPKG_COMMIT_ID }}
# doNotCache: false
```

### 步骤 11: 安装 vcpkg 依赖

```bash
# 设置环境变量
export VCPKG_DEFAULT_HOST_TRIPLET=x64-windows-static

# 安装依赖包
$VCPKG_ROOT/vcpkg install \
  --triplet x64-windows-static \
  --x-install-root="$VCPKG_ROOT/installed"

# 如果失败，输出所有日志
if [ $? -ne 0 ]; then
  find "${VCPKG_ROOT}/" -name "*.log" | while read -r _1; do
    echo "$_1:"
    echo "======"
    cat "$_1"
    echo "======"
    echo ""
  done
  exit 1
fi

# 输出 ffmpeg 构建日志前 100 行
head -n 100 "${VCPKG_ROOT}/buildtrees/ffmpeg/build-x64-windows-static-rel-out.log" || true
```

**依赖包** (从 vcpkg.json 读取):
- libvpx
- libyuv
- opus
- aom
- ffmpeg (可能)

### 步骤 12: 构建 RustDesk

#### 12.1 构建主程序

```powershell
# 使用 Python 构建脚本
python3 .\build.py --portable --hwcodec --flutter --vram --skip-portable-pack

# 移动构建产物
mv ./flutter/build/windows/x64/runner/Release ./rustdesk
```

**构建参数说明**:
- `--portable`: 构建便携版
- `--hwcodec`: 启用硬件编解码支持
- `--flutter`: 使用 Flutter UI
- `--vram`: 启用 VRAM 优化 (Windows 独有)
- `--skip-portable-pack`: 跳过便携版打包步骤

#### 12.2 下载并集成 USB 虚拟显示器驱动

```powershell
# 下载 usbmmidd_v2 驱动
Invoke-WebRequest -Uri https://github.com/rustdesk-org/rdev/releases/download/usbmmidd_v2/usbmmidd_v2.zip -OutFile usbmmidd_v2.zip

# 解压
Expand-Archive usbmmidd_v2.zip -DestinationPath .

# 删除不需要的 32 位驱动和工具
Remove-Item -Path usbmmidd_v2\Win32 -Recurse
Remove-Item -Path "usbmmidd_v2\deviceinstaller64.exe", "usbmmidd_v2\deviceinstaller.exe", "usbmmidd_v2\usbmmidd.bat"

# 移动到 rustdesk 目录
mv -Force .\usbmmidd_v2 ./rustdesk
```

#### 12.3 下载并集成打印机驱动 (带校验)

```powershell
try {
  # 下载打印机驱动文件
  Invoke-WebRequest -Uri https://github.com/rustdesk/hbb_common/releases/download/driver/rustdesk_printer_driver_v4-1.4.zip -OutFile rustdesk_printer_driver_v4-1.4.zip
  Invoke-WebRequest -Uri https://github.com/rustdesk/hbb_common/releases/download/driver/printer_driver_adapter.zip -OutFile printer_driver_adapter.zip
  Invoke-WebRequest -Uri https://github.com/rustdesk/hbb_common/releases/download/driver/sha256sums -OutFile sha256sums

  # 提取驱动的 SHA256 校验和
  $checksum_driver = (Select-String -Path .\sha256sums -Pattern '^([a-fA-F0-9]{64}) \*rustdesk_printer_driver_v4-1.4\.zip$').Matches.Groups[1].Value
  $downloadsum_driver = Get-FileHash -Path rustdesk_printer_driver_v4-1.4.zip -Algorithm SHA256

  # 提取适配器的 SHA256 校验和
  $checksum_adapter = (Select-String -Path .\sha256sums -Pattern '^([a-fA-F0-9]{64}) \*printer_driver_adapter\.zip$').Matches.Groups[1].Value
  $downloadsum_adapter = Get-FileHash -Path printer_driver_adapter.zip -Algorithm SHA256

  # 验证校验和并解压
  if ($checksum_driver -eq $downloadsum_driver.Hash -and $checksum_adapter -eq $downloadsum_adapter.Hash) {
    Write-Output "rustdesk_printer_driver_v4-1.4, checksums match, extract the file."

    # 解压驱动
    Expand-Archive rustdesk_printer_driver_v4-1.4.zip -DestinationPath .
    mkdir ./rustdesk/drivers
    mv -Force .\rustdesk_printer_driver_v4-1.4 ./rustdesk/drivers/RustDeskPrinterDriver

    # 解压适配器
    Expand-Archive printer_driver_adapter.zip -DestinationPath .
    mv -Force .\printer_driver_adapter.dll ./rustdesk
  }
  elseif ($checksum_driver -ne $downloadsum_driver.Hash) {
    Write-Output "rustdesk_printer_driver_v4-1.4, checksums do not match, ignore the file."
  }
  else {
    Write-Output "printer_driver_adapter.dll, checksums do not match, ignore the file."
  }
} catch {
  Write-Host "Ignore the printer driver error."
}
```

### 步骤 13: 查找并复制 Runner.res

```bash
# 查找 Runner.res 文件 (包含实际版本信息)
runner_res=$(find . -name "Runner.res")

if [ "$runner_res" == "" ]; then
  echo "Runner.res: not found"
else
  echo "Runner.res: $runner_res"

  # 复制到便携版目录
  cp $runner_res ./libs/portable/Runner.res

  # 列出文件信息
  echo "list ./libs/portable/Runner.res"
  ls -l ./libs/portable/Runner.res
fi
```

**说明**: Runner.res 由 ./flutter/windows/runner/Runner.rc 编译而来，包含实际的版本信息

### 步骤 14: 下载 RustDeskTempTopMostWindow 组件

```bash
# 使用 actions/download-artifact@master
# artifact name: topmostwindow-artifacts
# path: ./rustdesk
```

**条件**: 仅在 `upload-artifact == true` 时执行

### 步骤 15: 上传未签名版本

```bash
# 使用 actions/upload-artifact@master
# artifact name: rustdesk-unsigned-windows-x86_64
# path: rustdesk
```

**条件**: `UPLOAD_ARTIFACT == 'true'`

### 步骤 16: 签名 rustdesk 文件

```bash
# 安装 Python 依赖
pip3 install requests argparse

# 执行签名脚本
BASE_URL=${{ secrets.SIGN_BASE_URL }} \
SECRET_KEY=${{ secrets.SIGN_SECRET_KEY }} \
python3 res/job.py sign_files ./rustdesk/
```

**条件**: `UPLOAD_ARTIFACT == 'true' && SIGN_BASE_URL != ''`

### 步骤 17: 构建自解压可执行文件

```bash
# 修改 manifest.xml，移除 dpiAware 设置
sed -i '/dpiAware/d' res/manifest.xml

# 进入便携版目录
pushd ./libs/portable

# 安装 Python 依赖
pip3 install -r requirements.txt

# 生成自解压打包器
python3 ./generate.py \
  -f ../../rustdesk/ \
  -o . \
  -e ../../rustdesk/rustdesk.exe

popd

# 创建输出目录
mkdir -p ./SignOutput

# 移动生成的文件
mv ./target/release/rustdesk-portable-packer.exe ./SignOutput/rustdesk-${{ env.VERSION }}-x86_64.exe
```

**条件**: `UPLOAD_ARTIFACT == 'true'`

**输出**: `rustdesk-{VERSION}-x86_64.exe`

### 步骤 18: 添加 MSBuild 到 PATH

```bash
# 使用 microsoft/setup-msbuild@v2
```

### 步骤 19: 构建 MSI 安装包

```powershell
# 进入 MSI 项目目录
pushd ./res/msi

# 预处理 MSI 配置
python preprocess.py --arp -d ../../rustdesk

# 恢复 NuGet 包
nuget restore msi.sln

# 编译 MSI
msbuild msi.sln \
  -p:Configuration=Release \
  -p:Platform=x64 \
  /p:TargetVersion=Windows10

# 移动生成的 MSI 文件
mv ./Package/bin/x64/Release/en-us/Package.msi ../../SignOutput/rustdesk-${{ env.VERSION }}-x86_64.msi

# 生成 SHA256 校验和
sha256sum ../../SignOutput/rustdesk-*.msi
```

**条件**: `UPLOAD_ARTIFACT == 'true'`

**参数说明**:
- `--arp`: 添加到"添加/删除程序"
- `-d ../../rustdesk`: 指定源文件目录
- `Configuration=Release`: 发布版本
- `Platform=x64`: 64 位平台
- `TargetVersion=Windows10`: 目标 Windows 10

**输出**: `rustdesk-{VERSION}-x86_64.msi`

### 步骤 20: 签名自解压文件

```bash
# 签名 SignOutput 目录下的所有文件
BASE_URL=${{ secrets.SIGN_BASE_URL }} \
SECRET_KEY=${{ secrets.SIGN_SECRET_KEY }} \
python3 res/job.py sign_files ./SignOutput
```

**条件**: `UPLOAD_ARTIFACT == 'true' && SIGN_BASE_URL != ''`

### 步骤 21: 发布 Release

```yaml
# 使用 softprops/action-gh-release@v1
prerelease: true
tag_name: ${{ env.TAG_NAME }}
files:
  - ./SignOutput/rustdesk-*.msi
  - ./SignOutput/rustdesk-*.exe
```

**条件**: `UPLOAD_ARTIFACT == 'true'`

---

## 环境变量

需要在工作流中定义的环境变量:

- `LLVM_VERSION`: LLVM 版本号
- `FLUTTER_VERSION`: Flutter 版本号 (例如: 3.24.5)
- `SCITER_RUST_VERSION`: Rust 工具链版本
- `VCPKG_COMMIT_ID`: vcpkg Git 提交 ID
- `VERSION`: RustDesk 版本号
- `TAG_NAME`: Git 标签名称
- `UPLOAD_ARTIFACT`: 是否上传 artifact (true/false)

需要在 GitHub Secrets 中配置:

- `SIGN_BASE_URL`: 代码签名服务 URL
- `SIGN_SECRET_KEY`: 代码签名密钥

---

## 最终产物

### 1. 自解压便携版
- **文件名**: `rustdesk-{VERSION}-x86_64.exe`
- **位置**: `./SignOutput/`
- **特性**:
  - 单文件可执行
  - 无需安装
  - 包含所有驱动和依赖

### 2. MSI 安装包
- **文件名**: `rustdesk-{VERSION}-x86_64.msi`
- **位置**: `./SignOutput/`
- **特性**:
  - Windows Installer 包
  - 支持静默安装
  - 添加到"添加/删除程序"
  - 包含所有驱动和依赖

### 3. 未签名调试版本
- **artifact 名称**: `rustdesk-unsigned-windows-x86_64`
- **内容**: 完整的 rustdesk 目录
- **用途**: 调试和测试

---

## 集成的组件

### 1. USB 虚拟显示器驱动 (usbmmidd_v2)
- **源**: https://github.com/rustdesk-org/rdev/releases/download/usbmmidd_v2/usbmmidd_v2.zip
- **架构**: x64 only
- **位置**: `rustdesk/usbmmidd_v2/`

### 2. 打印机驱动 (v4-1.4)
- **源**: https://github.com/rustdesk/hbb_common/releases/download/driver/
- **文件**:
  - `rustdesk_printer_driver_v4-1.4.zip`
  - `printer_driver_adapter.zip`
- **位置**:
  - `rustdesk/drivers/RustDeskPrinterDriver/`
  - `rustdesk/printer_driver_adapter.dll`
- **验证**: SHA256 校验和

### 3. RustDeskTempTopMostWindow
- **源**: 前置构建任务
- **位置**: `rustdesk/`

---

## 构建特性

### 启用的功能
✅ Hardware codec (--hwcodec)
✅ VRAM optimization (--vram)
✅ Flutter UI (--flutter)
✅ Portable mode (--portable)
✅ USB virtual display driver
✅ Printer driver support
✅ Code signing

### 平台特定优化
- **VRAM**: Windows 独有的显存优化
- **自定义 Flutter 引擎**: 修复上游 bug
- **双安装方式**: EXE 和 MSI 两种分发格式

---

## 依赖项总结

### 系统工具
- Python 3
- Git
- MSBuild
- NuGet

### 开发工具
- LLVM/Clang
- Rust (MSVC toolchain)
- Flutter SDK
- vcpkg

### C/C++ 库 (via vcpkg)
- libvpx (视频编码)
- libyuv (图像处理)
- opus (音频编码)
- aom (AV1 编码)
- ffmpeg (可选)

### Python 包
- requests
- argparse
- (libs/portable/requirements.txt 中的其他依赖)

---

## 注意事项

1. **Flutter 引擎替换**: 必须使用 RustDesk 自定义引擎以修复上游问题
2. **驱动校验**: 打印机驱动下载后必须验证 SHA256
3. **签名顺序**: 先签名 rustdesk 目录下的文件，再签名最终的 EXE/MSI
4. **Runner.res**: 包含实际版本信息，需要复制到便携版目录
5. **DPI Aware**: manifest.xml 中的 dpiAware 设置在打包前被移除

---

## 故障排除

### vcpkg 安装失败
```bash
# 查看详细日志
find "${VCPKG_ROOT}/" -name "*.log"
```

### Flutter 引擎问题
```bash
# 验证引擎文件
ls -la C:/hostedtoolcache/windows/flutter/stable-{VERSION}-x64/bin/cache/artifacts/engine/windows-x64-release/
```

### 签名失败
检查环境变量:
- `SIGN_BASE_URL`
- `SIGN_SECRET_KEY`

---

## 参考链接

- [Flutter Issue #155685](https://github.com/flutter/flutter/issues/155685)
- [RustDesk Custom Flutter Engine](https://github.com/rustdesk/engine)
- [USB Virtual Display Driver](https://github.com/rustdesk-org/rdev)
- [Printer Driver Release](https://github.com/rustdesk/hbb_common/releases)

---

**文档版本**: 1.0
**更新日期**: 2025-10-18
**基于**: `.github/workflows/flutter-build.yml`
