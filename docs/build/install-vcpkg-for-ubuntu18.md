# vcpkg 依赖安装指南（支持 -fPIC）

## 概述

本脚本用于在 Ubuntu 18.04 环境中安装 RustDesk 的 vcpkg 依赖，并自动配置 Position Independent Code (PIC) 支持，解决共享库链接问题。

## 问题背景

### 症状

编译 RustDesk 时出现链接错误：

```
error: relocation R_X86_64_32S against `.rodata' can not be used
when making a shared object; recompile with -fPIC
```

### 根本原因

- RustDesk 构建 `librustdesk.so` 共享库（用于 Flutter FFI）
- vcpkg 默认编译静态库时不使用 `-fPIC` 标志
- 静态库（libopus, libyuv, libvpx, aom）链接到共享库时需要 PIC 支持

### 解决方案

使用 `install_vcpkg_deps.sh` 脚本自动处理：
1. 验证 vcpkg triplet 配置了 `-fPIC`
2. 清理所有缓存（包括关键的 status 文件）
3. 使用 `-fPIC` 环境变量重新编译所有依赖
4. 验证目标文件的 PIC 编译

## 使用方法

### 前提条件

1. 已运行 `scripts/setup-for-ubuntu18.sh` 配置 vcpkg triplet
2. vcpkg 已安装并 bootstrap 完成
3. 在 Ubuntu 18.04 环境中运行

### 快速开始

```bash
# 进入项目目录
cd /home/gongdewei/work/projects/rustdesk2

# 运行统一的 vcpkg 依赖安装脚本
bash scripts/install_vcpkg_deps.sh
```

该脚本会自动执行以下步骤：

### Step 0: 验证 -fPIC 配置

检查 `vcpkg/triplets/x64-linux.cmake` 是否包含：
```cmake
set(VCPKG_C_FLAGS "-fPIC")
set(VCPKG_CXX_FLAGS "-fPIC")
```

如果未配置，会给出警告并建议运行 `setup-for-ubuntu18.sh`。

### Step 1: 清理 vcpkg 缓存

完整清理所有缓存，包括：
- `vcpkg/installed/x64-linux/` - 已安装的库
- `vcpkg/buildtrees/` - 构建临时文件（包含缓存的对象文件）
- `vcpkg/packages/` - 打包文件
- **`vcpkg/installed/vcpkg/status`** - 状态数据库（关键！）

**为什么必须删除 status 文件？**
- 该文件记录了已安装包的状态
- vcpkg 用它判断是否需要重新编译
- 如果不删除，vcpkg 会认为包已安装，跳过重新编译
- 结果：继续使用旧的（无 -fPIC）二进制文件

### Step 2: 创建 Overlay Ports

为 Ubuntu 18.04 创建兼容的 overlay ports：

1. **AOM (AV1 编解码器)**
   - 修复 AVX2 兼容性问题
   - 禁用高级 SIMD 指令集（AVX2、SSE4.1、SSSE3）
   - 使用 generic CPU target

2. **libyuv (YUV 转换库)**
   - 使用兼容版本
   - 修复 CMake 配置路径问题

### Step 3: 安装 vcpkg 依赖

使用 `-fPIC` 环境变量安装所有依赖：

```bash
export CFLAGS="-fPIC"
export CXXFLAGS="-fPIC"

sudo CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" \
  $VCPKG_ROOT/vcpkg install --triplet x64-linux \
  --x-install-root="$VCPKG_ROOT/installed"
```

**为什么同时设置环境变量？**
- Triplet 配置确保 vcpkg 管理的包使用 `-fPIC`
- 环境变量确保 CMake 项目和特殊构建脚本也能看到这个标志
- 双重保险，避免遗漏

安装的主要依赖包括：
- `aom` - AV1 编解码器
- `libyuv` - YUV 缩放和转换
- `libvpx` - VP8/VP9 编解码器
- `opus` - 音频编解码器
- 其他依赖（根据 vcpkg.json）

### Step 4: 验证 PIC 编译

自动验证目标文件是否正确使用 PIC：

```bash
# 提取 libopus.a 中的第一个目标文件
ar x libopus.a <first_object>

# 检查绝对重定位数量
readelf -r <object_file> | grep -c "R_X86_64_32"
```

**验证结果：**
- ✅ **0 个绝对重定位** - PIC 编译正确
- ⚠️ **有绝对重定位** - 可能有问题，但不一定导致链接失败

## 手动验证

### 检查 triplet 配置

```bash
cat vcpkg/triplets/x64-linux.cmake
```

应该包含：
```cmake
set(VCPKG_C_FLAGS "-fPIC")
set(VCPKG_CXX_FLAGS "-fPIC")
```

### 检查已安装的库

```bash
INSTALL_DIR="vcpkg/installed/x64-linux"

# 检查库文件
ls -lh $INSTALL_DIR/lib/libaom.a
ls -lh $INSTALL_DIR/lib/libyuv.a
ls -lh $INSTALL_DIR/lib/libvpx.a
ls -lh $INSTALL_DIR/lib/libopus.a

# 检查头文件
ls $INSTALL_DIR/include/aom/aom_image.h
ls $INSTALL_DIR/include/libyuv.h
ls $INSTALL_DIR/include/vpx/vpx_codec.h
ls $INSTALL_DIR/include/opus/opus.h
```

### 验证 PIC 编译（详细）

```bash
# 进入临时目录
cd /tmp

# 提取 libopus.a 的目标文件
ar x /home/gongdewei/work/projects/rustdesk2/vcpkg/installed/x64-linux/lib/libopus.a \
  $(ar t /home/gongdewei/work/projects/rustdesk2/vcpkg/installed/x64-linux/lib/libopus.a | head -1)

# 检查重定位类型
readelf -r *.o | grep R_X86_64_32

# 期望结果：
# - 无输出或很少 = PIC 正确
# - 很多 R_X86_64_32 = 未使用 PIC
```

### 验证最终的共享库

```bash
# 检查文件类型
file target/release/liblibrustdesk.so

# 应该输出：
# target/release/liblibrustdesk.so: ELF 64-bit LSB shared object, x86-64, ...

# 检查 TEXTREL（文本段重定位）
readelf -d target/release/liblibrustdesk.so | grep TEXTREL

# 应该无输出（说明没有文本段重定位问题）
```

## 常见问题

### Q1: 脚本提示 "-fPIC 未配置在 triplet 中"

**原因：** 未运行 `setup-for-ubuntu18.sh` 或 triplet 配置被覆盖。

**解决：**
```bash
bash scripts/setup-for-ubuntu18.sh
```

### Q2: 安装后仍然报 PIC 错误

**可能原因：**
1. vcpkg status 文件未删除
2. Rust 构建缓存未清理
3. triplet 配置后 vcpkg 未重新安装

**解决：**
```bash
# 完整清理并重新安装
cd /home/gongdewei/work/projects/rustdesk2

# 清理 Rust 缓存
cargo clean

# 重新运行 vcpkg 安装
bash scripts/install_vcpkg_deps.sh
```

### Q3: vcpkg 安装很慢（15-25 分钟）

**正常现象：**
- AOM、FFmpeg 等需要从源码编译
- Ubuntu 18.04 编译器较老
- 优化级别高（Release 模式）

**加速方法：**
1. **CI 缓存**：GitHub Actions 缓存 `vcpkg/installed/`
2. **一次编译，多次使用**：保存整个 installed 目录
3. **并行编译**：vcpkg 默认使用多核

### Q4: 为什么不用系统库（linux-pkg-config）？

**方案对比：**

| 方案 | 优点 | 缺点 |
|------|------|------|
| **vcpkg + fPIC** | ✅ 版本可控<br>✅ 静态链接，单一二进制<br>✅ 不依赖系统库 | ⚠️ 需要配置 triplet<br>⚠️ 首次编译慢 |
| **system libs** | ✅ 快速，使用现成的<br>✅ 无需编译 | ❌ Ubuntu 18 缺少 libyuv<br>❌ 版本不可控<br>❌ 依赖系统环境 |

**结论：**
- **CI/发布版本**：推荐 vcpkg + fPIC（可控、可复现）
- **本地开发调试**：可考虑 system libs（快速迭代）

### Q5: 需要 root 权限吗？

**需要的操作：**
- 清理 vcpkg 缓存（某些文件由 root 创建）
- 安装 vcpkg 依赖（写入到 vcpkg/installed/）

**建议：**
```bash
# 如果遇到权限问题，使用 sudo
sudo bash scripts/install_vcpkg_deps.sh

# 或者清理后切换用户
sudo rm -rf vcpkg/installed vcpkg/buildtrees vcpkg/packages
bash scripts/install_vcpkg_deps.sh  # 普通用户
```

## 时间估算

| 步骤 | 时间 |
|------|------|
| Step 0: 验证配置 | < 1 秒 |
| Step 1: 清理缓存 | 30 秒 - 1 分钟 |
| Step 2: 创建 overlay ports | < 1 秒 |
| Step 3: 安装依赖 | 15-25 分钟 |
| Step 4: 验证 PIC | < 5 秒 |
| **总计** | **~15-30 分钟** |

**注意：**
- 第一次运行最慢（需要下载和编译所有依赖）
- 后续如果只是清理重装，vcpkg 会利用下载缓存
- 增量更新（只重新编译部分包）会更快

## 编译 RustDesk

vcpkg 依赖安装完成后：

```bash
# 1. 设置环境变量
export VCPKG_ROOT=$(pwd)/vcpkg

# 2. 编译 RustDesk
cargo build --features hwcodec,flutter,unix-file-copy-paste --release

# 3. 验证构建产物
ls -lh target/release/rustdesk
ls -lh target/release/service
ls -lh target/release/naming
ls -lh target/release/liblibrustdesk.so

# 4. 检查共享库（无 TEXTREL 警告）
readelf -d target/release/liblibrustdesk.so | grep TEXTREL
```

## CI/CD 集成

### GitHub Actions 示例

```yaml
- name: Install vcpkg dependencies with PIC support
  run: |
    cd ${{ github.workspace }}
    bash scripts/install_vcpkg_deps.sh

- name: Build RustDesk
  run: |
    export VCPKG_ROOT=${{ github.workspace }}/vcpkg
    cargo build --features hwcodec,flutter,unix-file-copy-paste --release
```

### 缓存优化

```yaml
- name: Cache vcpkg
  uses: actions/cache@v3
  with:
    path: |
      vcpkg/installed
      vcpkg/downloads
    key: vcpkg-${{ runner.os }}-${{ hashFiles('vcpkg.json') }}
```

## 技术细节

### Position Independent Code (PIC)

| 链接目标 | 需要 -fPIC? | 原因 |
|---------|------------|------|
| **可执行文件** (`rustdesk`) | ❌ 否 | 固定加载地址，链接时重定位 |
| **静态库** (`.rlib`, `.a`) | ❌ 否 | 只是打包，延迟到最终链接 |
| **共享库** (`librustdesk.so`) | ✅ **必须** | 无固定地址，运行时动态加载 |

**共享库为什么需要 PIC？**
1. 多个进程共享同一份代码段
2. 每个进程加载到不同的虚拟地址
3. 需要运行时重定位，不能修改代码段
4. PIC 使用 GOT（Global Offset Table）和 PLT（Procedure Linkage Table）实现位置无关

### 性能影响

PIC 代码的性能开销：
- 代码大小：稍大（额外的 GOT/PLT 表）
- CPU 开销：< 5%（额外的间接寻址）
- 远程桌面应用：**影响可忽略**（网络延迟远大于 CPU 开销）

## 相关文档

- [setup-for-ubuntu18-README.md](./setup-for-ubuntu18-README.md) - 环境设置详解
- [REBUILD-GUIDE.md](./REBUILD-GUIDE.md) - 重新编译指南
- [vcpkg Triplets 文档](https://vcpkg.io/en/docs/users/triplets.html)
- [Position Independent Code (Wikipedia)](https://en.wikipedia.org/wiki/Position-independent_code)

## 总结

**`install_vcpkg_deps.sh` 脚本整合了以下功能：**

1. ✅ **自动验证** -fPIC 配置
2. ✅ **完整清理** vcpkg 缓存（包括 status 文件）
3. ✅ **创建 overlay ports** 解决 Ubuntu 18.04 兼容性
4. ✅ **使用 -fPIC** 重新编译所有依赖
5. ✅ **自动验证** PIC 编译结果

**使用方式：**
```bash
bash scripts/install_vcpkg_deps.sh
```

一条命令完成所有 vcpkg 依赖的安装和配置！
