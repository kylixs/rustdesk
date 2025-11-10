# 编译和链接问题分析指南

全面的编译和链接问题诊断和解决指南，专注于 RustDesk 构建中的 vcpkg、Rust、Flutter、系统库和 PIC 要求。

## 目录
- [1. 库和头文件搜索路径](#1-库和头文件搜索路径)
  - [1.1 库搜索路径](#11-库搜索路径)
  - [1.2 头文件搜索路径](#12-头文件搜索路径)
  - [1.3 pkg-config 搜索路径](#13-pkg-config-搜索路径)
  - [1.4 常见搜索路径问题](#14-常见搜索路径问题)
- [2. 链接原理](#2-链接原理)
  - [2.1 静态链接 vs 动态链接](#21-静态链接-vs-动态链接)
  - [2.2 符号解析](#22-符号解析)
  - [2.3 位置无关代码 (PIC)](#23-位置无关代码-pic)
  - [2.4 可执行文件链接类型](#24-可执行文件链接类型)
    - [2.4.1 全静态链接](#241-全静态链接)
    - [2.4.2 动态链接](#242-动态链接)
    - [2.4.3 混合链接（静态库链接到共享库）](#243-混合链接静态库链接到共享库)
    - [2.4.4 对比表](#244-对比表)
    - [2.4.5 常见链接错误](#245-常见链接错误)
    - [2.4.6 判断二进制链接类型](#246-判断二进制链接类型)
    - [2.4.7 RustDesk Ubuntu 18.04 最佳实践](#247-rustdesk-ubuntu-1804-最佳实践)
- [3. 逐步检查方法](#3-逐步检查方法)
- [4. 必备工具](#4-必备工具)
- [5. vcpkg 集成](#5-vcpkg-集成)
- [6. Rust 链接](#6-rust-链接)
- [7. Flutter 编译](#7-flutter-编译)
- [8. 系统库冲突](#8-系统库冲突)
- [9. PIC 验证](#9-pic-验证)
- [10. 检查 .a 和 .o 文件](#10-检查-a-和-o-文件)

---

## 1. 库和头文件搜索路径

理解搜索路径对于诊断链接问题至关重要。

### 1.1 库搜索路径

库文件按以下顺序搜索：

#### **编译时链接**（构建时）：
1. **`-L` 参数**：通过 `-L /path/to/libs` 传递给链接器的显式路径
2. **`LIBRARY_PATH`**：GCC/G++ 链接器搜索的环境变量
3. **默认系统路径**：`/usr/lib`、`/usr/local/lib`、`/lib`

#### **运行时链接**（执行时）：
1. **`RPATH`/`RUNPATH`**：编译时嵌入二进制文件中
2. **`LD_LIBRARY_PATH`**：环境变量（最高优先级）
3. **`/etc/ld.so.conf`**：系统级库配置
4. **默认系统路径**：`/usr/lib`、`/usr/local/lib`、`/lib`

#### **在 build-for-ubuntu18.sh 中的示例**：
```bash
# 编译时库搜索（vcpkg 优先以覆盖系统库）
export LIBRARY_PATH="$VCPKG_INSTALLED/lib:/usr/lib/x86_64-linux-gnu:$LIBRARY_PATH"

# 运行时库搜索（用于运行构建工具）
export LD_LIBRARY_PATH="$VCPKG_INSTALLED/lib:/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"

# Rust 链接器标志（vcpkg 优先）
export RUSTFLAGS="-L $VCPKG_INSTALLED/lib -L /usr/lib/x86_64-linux-gnu"
```

**为什么 vcpkg 要放在最前面？**
- Ubuntu 18.04 上的系统库缺少 PIC（位置无关代码）
- vcpkg 库使用 `-fPIC -DPIC` 编译
- 链接器使用找到的第一个匹配库
- 因此 vcpkg 路径必须在系统路径之前

#### **检查库搜索顺序**：
```bash
# 检查编译时搜索路径
gcc -print-search-dirs | grep libraries

# 检查二进制文件的运行时搜索路径
ldd /path/to/binary

# 检查将使用哪个库
ld --verbose | grep SEARCH_DIR
```

### 1.2 头文件搜索路径

头文件按以下顺序搜索：

#### **C 编译器 (gcc)**：
1. **`-I` 参数**：通过 `-I /path/to/includes` 的显式路径
2. **当前目录**：`.`（用于 `#include "file.h"`）
3. **`C_INCLUDE_PATH`**：环境变量
4. **`CPATH`**：环境变量（C 和 C++ 共用）
5. **默认系统路径**：`/usr/include`、`/usr/local/include`
6. **GCC 内部路径**：`/usr/lib/gcc/x86_64-linux-gnu/7/include`

#### **C++ 编译器 (g++)**：
1. **`-I` 参数**：通过 `-I /path/to/includes` 的显式路径
2. **当前目录**：`.`
3. **`CPLUS_INCLUDE_PATH`**：环境变量（C++ 专用）
4. **`CPATH`**：环境变量（C 和 C++ 共用）
5. **默认 C++ 路径**：`/usr/include/c++/7`、`/usr/include/x86_64-linux-gnu/c++/7`
6. **默认系统路径**：`/usr/include`、`/usr/local/include`

#### **在 build-for-ubuntu18.sh 中的示例**：
```bash
# 追加 vcpkg 头文件（系统默认路径有优先级）
export C_INCLUDE_PATH="$C_INCLUDE_PATH:$VCPKG_INSTALLED/include"
export CPLUS_INCLUDE_PATH="$CPLUS_INCLUDE_PATH:$VCPKG_INSTALLED/include"

# Flutter Linux 构建
export CPATH="/usr/include/c++/7:/usr/include/x86_64-linux-gnu/c++/7"
```

**为什么追加而不是前置？**
- 系统头文件通常是正确的，应该首先使用
- vcpkg 头文件只用于系统上不可用的库
- 防止与系统头文件冲突

#### **检查头文件搜索顺序**：
```bash
# 检查 C 头文件路径
gcc -x c -E -v - < /dev/null 2>&1 | grep '^ '

# 检查 C++ 头文件路径
g++ -x c++ -E -v - < /dev/null 2>&1 | grep '^ '

# 检查特定头文件
gcc -H -c test.c -o /dev/null
```

### 1.3 pkg-config 搜索路径

pkg-config 帮助查找库和头文件路径：

```bash
# pkg-config 搜索路径（优先级从高到低）
export PKG_CONFIG_PATH="/usr/lib/x86_64-linux-gnu/pkgconfig:$VCPKG_INSTALLED/lib/pkgconfig:$PKG_CONFIG_PATH"

# 检查 pkg-config 找到什么
pkg-config --libs libavcodec
pkg-config --cflags libavcodec
pkg-config --modversion libavcodec

# 调试 pkg-config 搜索
PKG_CONFIG_DEBUG_SPEW=1 pkg-config --libs libavcodec
```

### 1.4 常见搜索路径问题

| 问题 | 症状 | 解决方案 |
|------|------|----------|
| 使用了错误的库版本 | 链接到系统库而不是 vcpkg | 将 vcpkg 放在 `LIBRARY_PATH` 最前面 |
| 找不到头文件 | `fatal error: xxx.h: No such file` | 添加到 `C_INCLUDE_PATH` 或 `-I` |
| 使用了错误的头文件 | 编译通过但链接失败 | 使用 `-H` 检查头文件搜索顺序 |
| 运行时找不到库 | `error while loading shared libraries` | 设置 `LD_LIBRARY_PATH` 或使用 RPATH |
| pkg-config 找不到库 | `Package xxx was not found` | 将 .pc 文件位置添加到 `PKG_CONFIG_PATH` |

---

## 2. 链接原理

### 2.1 静态链接 vs 动态链接

**静态链接**（`.a` 文件）：
- 库代码复制到最终二进制文件中
- 无运行时依赖
- 二进制文件更大
- 包含到共享库时需要 PIC

**动态链接**（`.so` 文件）：
- 二进制文件引用外部库
- 二进制文件更小
- 进程间共享
- 运行时需要库

### 2.2 符号解析

链接器按顺序解析符号：
1. 已定义的符号（跳过）
2. 搜索目标文件（`.o`）
3. 搜索静态库（`.a`）- 按指定顺序
4. 搜索动态库（`.so`）- 按搜索路径顺序

**重要**：顺序很重要！库 B 依赖 A？链接为：`-lB -lA`

### 2.3 位置无关代码 (PIC)

**什么是 PIC？**
- 可以在任何内存地址运行的代码
- 共享库（`.so`）所需
- 使用 `-fPIC` 标志编译
- 使用相对寻址而不是绝对寻址

**PIC 对 RustDesk Ubuntu 18.04 为何重要：**
- 系统库（libopus、libaom、libvpx）未使用 PIC 编译
- Rust 构建共享库 `liblibrustdesk.so`
- 无法在共享库中包含非 PIC 代码
- vcpkg 库必须使用 `-fPIC -DPIC` 构建

**PIC 错误示例：**
```
error: could not compile `magnum-opus`
relocation R_X86_64_32 against `.rodata' can not be used when making a shared object
```

这意味着：在构建共享库时发现非 PIC 代码（绝对重定位）。

### 2.4 可执行文件链接类型

理解不同的链接策略对于构建各种类型的二进制文件至关重要。

#### **2.4.1 全静态链接**

**什么是全静态链接？**
- 所有库（包括 libc）编译到可执行文件中
- 运行时无外部 .so 依赖
- 单个自包含二进制文件

**如何创建：**
```bash
# C/C++
gcc -static main.c -o myapp
g++ -static main.cpp -o myapp

# Rust
cargo build --target x86_64-unknown-linux-musl  # 使用 musl libc（静态）
# 或
RUSTFLAGS="-C target-feature=+crt-static" cargo build --release
```

**优点：**
- ✓ 无运行时依赖
- ✓ 可在任何 Linux 系统上运行（相同架构）
- ✓ 无库版本冲突
- ✓ 易于分发

**缺点：**
- ✗ 二进制文件非常大（10-100MB+）
- ✗ 无法使用系统库（NSS、PAM 等）
- ✗ 无安全更新，必须重新编译
- ✗ 内存使用更高（进程间无共享）

**何时使用：**
- 嵌入式系统
- 容器化应用（scratch/distroless 镜像）
- 分发到未知环境
- 必须无依赖工作的工具

**示例：**
```bash
# 静态二进制示例
gcc -static hello.c -o hello
file hello
# 输出：ELF 64-bit LSB executable, x86-64, statically linked

ldd hello
# 输出：not a dynamic executable

ls -lh hello
# 大小：~800KB（vs 动态的 ~16KB）
```

#### **2.4.2 动态链接**

**什么是动态链接？**
- 可执行文件引用外部 .so 文件
- 运行时由动态链接器加载库
- Linux 上最常见的链接方法

**如何创建：**
```bash
# C/C++（默认行为）
gcc main.c -o myapp
g++ main.cpp -o myapp

# Rust（默认）
cargo build --release
```

**运行时库搜索：**
```
1. RPATH/RUNPATH（嵌入二进制文件中）
2. LD_LIBRARY_PATH 环境变量
3. /etc/ld.so.cache（来自 /etc/ld.so.conf）
4. /lib、/usr/lib（默认系统路径）
```

**优点：**
- ✓ 二进制文件小
- ✓ 进程间共享内存
- ✓ 无需重新编译即可安全更新
- ✓ 支持插件和模块

**缺点：**
- ✗ 运行时需要库
- ✗ 库版本冲突（"DLL 地狱"）
- ✗ 需要依赖管理

**何时使用：**
- 桌面应用
- 系统工具
- 受控环境中的应用
- 使用系统库（GTK、Qt 等）时

**示例：**
```bash
# 动态二进制示例
gcc hello.c -o hello
file hello
# 输出：ELF 64-bit LSB executable, x86-64, dynamically linked

ldd hello
# 输出：
#   linux-vdso.so.1 =>  (0x00007fff1234abcd)
#   libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007f1234567890)
#   /lib64/ld-linux-x86-64.so.2 (0x00007f9876543210)

ls -lh hello
# 大小：~16KB
```

#### **2.4.3 混合链接（静态库链接到共享库）**

**什么是混合链接？**
- 构建包含静态库（.a）的共享库（.so）
- 最终 .so 包含 .a 文件的代码
- RustDesk 使用这种方法！

**工作原理：**

```
源代码              静态库              共享库
  (Rust)             (.a)               (.so)
    ↓                 ↓                   ↓
  *.rs    →  [rustc] → *.o  ┐
                             ├→ [链接器] → liblibrustdesk.so
  libopus.a     ──────────→ ┘
  libaom.a      ──────────→ ┘
  libvpx.a      ──────────→ ┘
```

**关键要求：所有静态库必须是 PIC！**

**为什么需要 PIC：**
- 共享库（.so）在任意内存地址加载
- 代码必须使用位置无关寻址
- 非 PIC 代码有绝对内存引用 → 失败
- 这是 Ubuntu 18.04 PIC 错误的根本原因

**构建包含静态库的 .so：**

```bash
# 使用 PIC 编译静态库
gcc -c -fPIC -DPIC opus_encoder.c -o opus_encoder.o
ar rcs libopus.a opus_encoder.o

# 将静态库链接到共享库
gcc -shared -fPIC -o libmylib.so mycode.o -L. -lopus

# Rust 示例（RustDesk 场景）
# 1. 静态库：libopus.a、libaom.a、libvpx.a（都有 PIC）
# 2. Rust 代码编译为 .o 文件
# 3. 链接器创建包含静态库代码的 liblibrustdesk.so
cargo build --release  # 生成 target/release/liblibrustdesk.so
```

**检查 .so 是否包含 .a 的代码：**

```bash
# 从静态库提取符号
nm libopus.a | grep "T opus_encode"

# 检查符号是否存在于 .so 中
nm liblibrustdesk.so | grep "opus_encode"
# 如果找到 → 静态库代码已包含

# 检查 .so 大小（会更大）
ls -lh liblibrustdesk.so
# 大小包含所有静态库代码
```

**优点：**
- ✓ 捆绑特定库版本
- ✓ 控制库构建（例如 PIC 标志）
- ✓ 更少的运行时依赖
- ✓ 仍可在进程间共享

**缺点：**
- ✗ .so 文件更大
- ✗ 静态库代码无法独立更新
- ✗ 所有静态库必须是 PIC（严格要求）

**何时使用：**
- 自定义构建的库（vcpkg）
- 需要特殊编译标志的库
- 捆绑特定版本
- 避免系统库冲突

**RustDesk 示例：**

```bash
# vcpkg 构建 PIC 静态库
vcpkg install opus:x64-linux  # 创建带 -fPIC -DPIC 的 libopus.a

# Rust 将静态库链接到共享库
RUSTFLAGS="-L vcpkg/installed/x64-linux/lib" cargo build --release

# 结果：liblibrustdesk.so 包含 opus、aom、vpx 代码
file target/release/liblibrustdesk.so
# 输出：ELF 64-bit LSB shared object, x86-64

nm target/release/liblibrustdesk.so | grep opus_encode
# 输出：00000000012abcd0 T opus_encode  （符号存在）

ls -lh target/release/liblibrustdesk.so
# 大小：~50MB（包含所有静态库代码）
```

#### **2.4.4 对比表**

| 方面 | 全静态 | 动态 | 混合 (静态→.so) |
|------|--------|------|-----------------|
| 二进制大小 | 非常大 (MB) | 小 (KB) | 大 (MB) |
| 运行时依赖 | 无 | 多个 .so 文件 | 较少 .so 文件 |
| PIC 要求 | 否 | N/A（.so 需要：是） | **是（关键！）** |
| 共享 | 无共享 | 共享内存 | 共享内存 |
| 更新 | 重新编译 | 独立 | 混合 |
| 使用场景 | 嵌入式/容器 | 桌面应用 | 自定义库捆绑 |
| RustDesk | 否 | 否 | **是（当前）** |

#### **2.4.5 常见链接错误**

| 错误 | 链接类型 | 原因 | 解决方案 |
|------|----------|------|----------|
| `relocation R_X86_64_32 against '.rodata'` | 静态→.so | 非 PIC 静态库 | 使用 `-fPIC -DPIC` 重新构建 .a |
| `undefined reference to 'symbol'` | 任何 | 缺少库或顺序错误 | 添加库，检查 `-l` 顺序 |
| `error while loading shared libraries` | 动态 | 运行时找不到 .so | 设置 `LD_LIBRARY_PATH` 或 RPATH |
| `cannot find -lxxx` | 任何 | 库不在搜索路径中 | 添加到 `LIBRARY_PATH` 或 `-L` |
| 二进制文件太大 | 全静态 | 包含所有代码 | 使用动态或混合 |
| `GLIBC_2.XX not found` | 动态 | 在较新系统上构建 | 在旧系统上构建或使用静态 |

#### **2.4.6 判断二进制链接类型**

```bash
# 检查是静态还是动态
file mybinary
# "statically linked" → 全静态
# "dynamically linked" → 动态或混合

# 检查依赖
ldd mybinary
# "not a dynamic executable" → 全静态
# 列出 .so 文件 → 动态或混合

# 检查 .so 是否包含静态库代码
nm -D libmylib.so | grep symbol_from_static_lib
# 找到符号 → 混合（包含静态代码）
# 未找到符号 → 纯动态

# 检查 .so 中的 PIC
readelf -d libmylib.so | grep TEXTREL
# 无输出 → PIC 兼容 ✓
# 有 TEXTREL → 非 PIC ✗（会失败）
```

#### **2.4.7 RustDesk Ubuntu 18.04 最佳实践**

**问题**：系统静态库缺少 PIC → 无法链接到 .so

**解决方案**：使用 PIC 标志的 vcpkg

```bash
# 1. 使用 PIC 构建 vcpkg 库
vcpkg/triplets/x64-linux.cmake:
  set(VCPKG_C_FLAGS "-fPIC -DPIC")
  set(VCPKG_CXX_FLAGS "-fPIC -DPIC")

# 2. 安装 PIC 库
vcpkg install opus:x64-linux --overlay-ports=res/vcpkg/opus

# 3. 验证 PIC
readelf -r vcpkg/installed/x64-linux/lib/libopus.a | grep "R_X86_64_32[^S]"
# 应该为空或极少

# 4. 使用正确的路径顺序链接（vcpkg 优先）
export LIBRARY_PATH="$VCPKG_INSTALLED/lib:/usr/lib/x86_64-linux-gnu"
export RUSTFLAGS="-L $VCPKG_INSTALLED/lib -L /usr/lib/x86_64-linux-gnu"

# 5. 构建
cargo build --release

# 6. 验证最终 .so
readelf -d target/release/liblibrustdesk.so | grep TEXTREL
# 无输出 → 成功 ✓
```

**为什么使用这种方法？**
- RustDesk 需要共享库用于 Flutter 集成
- 必须包含编解码器库（opus、aom、vpx）
- Ubuntu 18.04 上的系统库不兼容 PIC
- vcpkg 构建自定义 PIC 版本
- 混合链接：静态编解码器库 → liblibrustdesk.so

---

## 3. 逐步检查方法

### 3.1 诊断工作流

```
问题发生
    ↓
是编译错误吗？
    ↓ 是
    检查头文件路径（第 1.2 节）
    检查编译器标志（第 7 节）
    ↓ 否
是链接错误吗？
    ↓ 是
    检查库搜索路径（第 1.1 节）
    检查库格式（.a vs .so）（第 4.3 节）
    检查 PIC 问题（第 9 节）
    ↓ 否
是运行时错误吗？
    ↓ 是
    检查 LD_LIBRARY_PATH（第 1.1 节）
    检查二进制文件中的 RPATH（第 4.5 节）
    检查库依赖（第 4.6 节）
```

### 3.2 常见错误模式

| 错误模式 | 可能原因 | 检查方法 |
|----------|----------|----------|
| `cannot find -lxxx` | 库不在搜索路径中 | 检查 `LIBRARY_PATH`，使用 `find` |
| `undefined reference to 'xxx'` | 缺少库或顺序错误 | 使用 `nm` 查找符号，重新排序库 |
| `relocation R_X86_64_32` | 共享库中的非 PIC 代码 | 使用 `readelf -r` 检查，用 PIC 重新构建 |
| `xxx.h: No such file` | 缺少头文件路径 | 检查 `C_INCLUDE_PATH`，使用 `gcc -H` |
| `version 'GLIBC_2.XX' not found` | 为较新的 glibc 编译的二进制文件 | 在旧系统上重新构建或使用兼容层 |

---

## 4. 必备工具

### 4.1 `file` - 识别文件类型

```bash
# 检查文件类型
file target/release/liblibrustdesk.so
# 输出：ELF 64-bit LSB shared object, x86-64

# 检查库是 32 位还是 64 位
file vcpkg/installed/x64-linux/lib/libopus.a
# 输出：current ar archive（表示静态库）

# 批量检查
find vcpkg/installed/x64-linux/lib -name "*.a" -exec file {} \;
```

### 4.2 `nm` - 列出符号

```bash
# 列出目标文件中的所有符号
nm libopus.a

# 仅显示已定义的符号
nm -g libopus.a | grep " T "

# 仅显示未定义的符号
nm -u hwcodec.o

# 搜索特定符号
nm -A vcpkg/installed/x64-linux/lib/*.a | grep opus_encode

# 检查符号是否存在
nm libopus.a | grep "T opus_encoder_create"
```

**符号类型：**
- `T` - 文本段（代码）- 已定义
- `U` - 未定义（需要解析）
- `D` - 初始化数据
- `B` - 未初始化数据（BSS）
- `R` - 只读数据
- `W` - 弱符号

### 4.3 `ar` - 归档工具

```bash
# 列出 .a 文件内容
ar -t libopus.a

# 从归档中提取目标文件
ar -x libopus.a

# 提取特定文件
ar -x libopus.a opus_encoder.o

# 创建静态库
ar rcs libmylib.a file1.o file2.o
```

### 4.4 `readelf` - ELF 信息

```bash
# 检查是否使用 PIC 编译（查找 TEXTREL）
readelf -d libopus.a | grep TEXTREL
# 无输出 = PIC，存在 TEXTREL = 非 PIC

# 显示重定位（绝对重定位 = 非 PIC）
readelf -r opus_encoder.o | grep R_X86_64_32

# 检查库依赖
readelf -d liblibrustdesk.so | grep NEEDED

# 显示段
readelf -S libopus.a

# 显示符号（类似 nm）
readelf -s libopus.a
```

### 4.5 `objdump` - 目标文件转储

```bash
# 反汇编代码
objdump -d libopus.a

# 显示所有头
objdump -x libopus.a

# 检查重定位
objdump -r opus_encoder.o

# 显示动态段
objdump -p liblibrustdesk.so

# 检查是否为 PIC（查找 @PLT 调用）
objdump -d libopus.a | grep @PLT
```

### 4.6 `ldd` - 列出动态依赖

```bash
# 显示运行时库依赖
ldd target/release/liblibrustdesk.so

# 显示所有依赖包括间接依赖
ldd -v target/release/liblibrustdesk.so

# 检查缺少的依赖
ldd target/release/liblibrustdesk.so | grep "not found"

# 显示实际加载的库
LD_DEBUG=libs ldd target/release/liblibrustdesk.so
```

### 4.7 `pkg-config` - 库配置

```bash
# 获取编译标志
pkg-config --cflags libavcodec

# 获取链接标志
pkg-config --libs libavcodec

# 检查版本
pkg-config --modversion libavcodec

# 检查包是否存在
pkg-config --exists libavcodec && echo "找到" || echo "未找到"

# 调试搜索
PKG_CONFIG_DEBUG_SPEW=1 pkg-config --libs libavcodec
```

### 4.8 `strings` - 提取字符串

```bash
# 在二进制文件中查找字符串
strings libopus.a | grep -i version

# 搜索特定文本
strings target/release/liblibrustdesk.so | grep opus
```

### 4.9 综合检查脚本

```bash
#!/bin/bash
# check-library.sh - 综合库检查

LIB=$1

echo "===== 文件类型 ====="
file "$LIB"

echo -e "\n===== 符号（前 20 个）====="
nm -g "$LIB" | head -20

echo -e "\n===== PIC 检查（TEXTREL = 不好）====="
readelf -d "$LIB" 2>/dev/null | grep TEXTREL || echo "✓ 无 TEXTREL（PIC 兼容）"

echo -e "\n===== 重定位（R_X86_64_32 = 非 PIC）====="
readelf -r "$LIB" 2>/dev/null | grep -E "R_X86_64_(32|PC32)" | head -5 || echo "✓ 无绝对重定位"

if [[ "$LIB" == *.so ]]; then
    echo -e "\n===== 依赖 ====="
    ldd "$LIB" | head -10
fi
```

使用方法：
```bash
bash check-library.sh vcpkg/installed/x64-linux/lib/libopus.a
```

---

## 5. vcpkg 集成

### 5.1 vcpkg 库结构

```
vcpkg/
├── installed/
│   └── x64-linux/
│       ├── lib/              # 静态库（.a）
│       ├── include/          # 头文件
│       ├── share/            # CMake 配置、pkg-config 文件
│       └── debug/lib/        # 调试库
├── packages/                 # 构建产物
├── buildtrees/               # 构建目录
└── downloads/                # 源代码下载
```

### 5.2 vcpkg Triplet 配置

Triplet 定义库的构建方式。对于 Ubuntu 18.04，我们使用 `x64-linux`：

**`vcpkg/triplets/x64-linux.cmake`**：
```cmake
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)  # 构建静态库

set(VCPKG_CMAKE_SYSTEM_NAME Linux)

# 关键：为 Ubuntu 18.04 添加 PIC 标志
set(VCPKG_C_FLAGS "-fPIC -DPIC")
set(VCPKG_CXX_FLAGS "-fPIC -DPIC")
set(VCPKG_C_FLAGS_RELEASE "-O3 -DNDEBUG -fPIC -DPIC")
set(VCPKG_CXX_FLAGS_RELEASE "-O3 -DNDEBUG -fPIC -DPIC")
```

**为什么需要 `-DPIC` 宏？**
- 某些构建系统检查 `#ifdef PIC` 来启用特定于 PIC 的代码
- `-fPIC` 是编译器标志，`-DPIC` 是预处理器宏
- 两者都需要完整的 PIC 兼容性

### 5.3 Ubuntu 18.04 的覆盖端口

覆盖端口使用自定义构建覆盖默认 vcpkg 端口：

```bash
# 使用覆盖安装
vcpkg install opus:x64-linux --overlay-ports=res/vcpkg/opus

# 覆盖端口结构
res/vcpkg/
├── opus/
│   ├── portfile.cmake       # 带 -DPIC 的构建指令
│   └── vcpkg.json           # 包元数据
├── aom/
└── libyuv/
```

**opus 的 `portfile.cmake` 示例**：
```cmake
vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-shared
        --enable-static
        --enable-float-approx
        CFLAGS=-fPIC\ -DPIC
        CXXFLAGS=-fPIC\ -DPIC
)
```

### 5.4 验证 vcpkg 库

```bash
# 检查 vcpkg 库是否有 PIC
readelf -d vcpkg/installed/x64-linux/lib/libopus.a | grep TEXTREL
# 应该无输出（PIC 兼容）

# 检查重定位
readelf -r vcpkg/installed/x64-linux/lib/libopus.a | grep R_X86_64_32
# 应该极少或没有

# 验证所有 vcpkg 库
for lib in vcpkg/installed/x64-linux/lib/*.a; do
    echo "检查 $lib..."
    readelf -r "$lib" | grep -q "R_X86_64_32[^S]" && echo "  ✗ 非 PIC" || echo "  ✓ PIC"
done
```

### 5.5 重新构建 vcpkg 库

```bash
# 清理特定库
cd vcpkg
rm -rf packages/opus_x64-linux
rm -rf buildtrees/opus
rm -rf installed/x64-linux/lib/libopus.*

# 使用 PIC 重新构建
CFLAGS="-fPIC -DPIC" CXXFLAGS="-fPIC -DPIC" \
  ./vcpkg install opus:x64-linux --overlay-ports=../res/vcpkg/opus

# 验证重新构建
readelf -d installed/x64-linux/lib/libopus.a | grep TEXTREL
```

---

## 6. Rust 链接

### 6.1 Rust 链接器行为

Rust 使用系统链接器（ld）和额外配置：

```bash
# 检查 Rust 使用哪个链接器
rustc --print cfg | grep target

# 详细链接输出
cargo build --verbose
# 显示完整链接器命令
```

### 6.2 RUSTFLAGS

通过 `RUSTFLAGS` 控制链接器行为：

```bash
# 添加库搜索路径（最高优先级）
export RUSTFLAGS="-L $VCPKG_INSTALLED/lib -L /usr/lib/x86_64-linux-gnu"

# 链接特定库
export RUSTFLAGS="-L /path/to/lib -l static=mylib"

# 详细链接
export RUSTFLAGS="-C link-arg=-Wl,--verbose"

# 检查 Rust 将使用什么
cargo rustc -- --print native-static-libs
```

**RUSTFLAGS 中的库搜索顺序：**
- 第一个 `-L` 路径具有最高优先级
- 因此：vcpkg 路径在系统路径之前

### 6.3 build.rs 脚本

Cargo 依赖可以使用 `build.rs` 配置链接：

**magnum-opus 的示例**：
```rust
// magnum-opus build.rs
fn main() {
    pkg_config::Config::new()
        .atleast_version("1.1")
        .probe("opus")
        .unwrap();
}
```

这使用 pkg-config 查找 opus。**问题**：如果 `PKG_CONFIG_PATH` 错误，它会找到系统 libopus（非 PIC）而不是 vcpkg libopus（PIC）。

**解决方案**：设置正确的 PKG_CONFIG_PATH：
```bash
export PKG_CONFIG_PATH="/usr/lib/x86_64-linux-gnu/pkgconfig:$VCPKG_INSTALLED/lib/pkgconfig"
# 系统优先用于 GTK/X11，vcpkg 其次用于编解码器
```

### 6.4 调试 Rust 链接错误

```bash
# 查看完整编译器命令
cargo build -vv 2>&1 | tee build-verbose.log

# 查找正在链接哪个库
grep "libopus" build-verbose.log

# 检查是否为 PIC 错误
grep "relocation R_X86_64" build-verbose.log

# 查看链接器命令
grep "^\s*rustc.*--crate-type" build-verbose.log

# 提取链接器标志
grep -o -- "-L [^ ]*" build-verbose.log | sort -u
```

### 6.5 常见 Rust 链接问题

| 错误 | 原因 | 解决方案 |
|------|------|----------|
| `could not compile 'hwcodec'` 带 PIC 错误 | 非 PIC FFmpeg 库 | 使用 PIC 重新构建 vcpkg FFmpeg |
| `could not compile 'magnum-opus'` 带 PIC 错误 | 非 PIC opus 库 | 使用 vcpkg opus，修复 `PKG_CONFIG_PATH` |
| `ld: cannot find -lopus` | opus 不在库搜索路径中 | 添加到 `RUSTFLAGS` 或 `LIBRARY_PATH` |
| 构建使用系统库而不是 vcpkg | 搜索路径顺序错误 | 在所有路径中将 vcpkg 放在最前面 |

### 6.6 Cargo 缓存问题

Cargo 缓存构建结果。修复 PIC 问题后，清理缓存：

```bash
# 清理特定依赖
rm -rf target/release/deps/libhwcodec*
rm -rf target/release/deps/libmagnum_opus*
rm -rf target/release/build/hwcodec-*
rm -rf target/release/build/magnum-opus-*

# 清理 git 依赖
rm -rf ~/.cargo/git/checkouts/hwcodec-*/
rm -rf ~/.cargo/git/checkouts/magnum-opus-*/

# 完全清理（最后手段）
cargo clean
```

---

## 7. Flutter 编译

### 7.1 Flutter 原生库集成

Flutter 桌面应用在运行时加载 Rust 库：

```
flutter/build/linux/x64/release/bundle/
├── rustdesk                    # Flutter 可执行文件
├── lib/
│   └── liblibrustdesk.so      # Rust 共享库（从 target/release/ 复制）
└── data/
```

Flutter 期望 `liblibrustdesk.so` 在 `lib/` 目录中。

### 7.2 Flutter 构建过程

```bash
# Flutter 构建调用：
flutter build linux --release

# 内部运行：
1. cmake（配置构建）
2. make（编译 C++ 包装器）
3. 从 target/release/ 复制 liblibrustdesk.so
4. 打包到 bundle/
```

### 7.3 C++ 头文件路径问题

Flutter 使用 C++，需要标准库头文件：

```bash
# 常见错误
fatal error: cstdlib: No such file or directory

# 解决方案：设置 CPATH
GCC_VERSION=$(gcc -dumpversion | cut -d. -f1)
export CPATH="/usr/include/c++/${GCC_VERSION}:/usr/include/x86_64-linux-gnu/c++/${GCC_VERSION}"
```

**为什么会这样：**
- Flutter 构建系统不自动检测 C++ 路径
- Ubuntu 18.04 GCC 7 有非标准头文件位置
- 设置 `CPATH` 添加到头文件搜索

### 7.4 Flutter 构建脚本依赖

```bash
# scripts/flutter_build.sh
python3 ./build.py --flutter --skip-cargo

# build.py 要求：
# - target/release/liblibrustdesk.so 必须存在
# - PATH 中有 Flutter SDK
# - 设置 C++ 头文件路径
```

### 7.5 调试 Flutter 构建

```bash
# 详细 Flutter 构建
flutter build linux --release --verbose

# 检查 CMake 配置
cat build/linux/x64/release/CMakeCache.txt

# 检查 Flutter 链接哪些库
ldd build/linux/x64/release/bundle/rustdesk

# 检查是否找到 Rust 库
ls -lh build/linux/x64/release/bundle/lib/liblibrustdesk.so
```

---

## 8. 系统库冲突

### 8.1 Ubuntu 18.04 系统库问题

**问题**：系统库未使用 PIC 编译：

```bash
# 检查系统 opus
readelf -r /usr/lib/x86_64-linux-gnu/libopus.a | grep R_X86_64_32
# 输出：许多 R_X86_64_32 重定位（非 PIC）

# 检查 vcpkg opus
readelf -r vcpkg/installed/x64-linux/lib/libopus.a | grep R_X86_64_32
# 输出：无或极少（PIC）
```

### 8.2 库搜索优先级

**关键**：vcpkg 必须放在最前面：

```bash
# ✗ 错误 - 系统优先
export LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:$VCPKG_INSTALLED/lib"
# 结果：链接非 PIC 系统库 → PIC 错误

# ✓ 正确 - vcpkg 优先
export LIBRARY_PATH="$VCPKG_INSTALLED/lib:/usr/lib/x86_64-linux-gnu"
# 结果：链接 PIC vcpkg 库 → 成功
```

### 8.3 混合系统/vcpkg 策略

某些库应使用系统，其他使用 vcpkg：

| 库 | 来源 | 原因 |
|----|------|------|
| GTK | 系统 | 系统集成，无 PIC 问题 |
| X11 | 系统 | 系统集成，无 PIC 问题 |
| pulse | 系统 | 音频系统集成 |
| opus | vcpkg | 系统版本非 PIC |
| aom | vcpkg | 系统版本非 PIC |
| vpx | vcpkg | 系统版本非 PIC |
| FFmpeg | vcpkg | 系统版本非 PIC，需要自定义配置 |

**实现**：
```bash
# pkg-config：系统优先（用于 GTK/X11）
export PKG_CONFIG_PATH="/usr/lib/x86_64-linux-gnu/pkgconfig:$VCPKG_INSTALLED/lib/pkgconfig"

# 库链接：vcpkg 优先（覆盖系统编解码器）
export LIBRARY_PATH="$VCPKG_INSTALLED/lib:/usr/lib/x86_64-linux-gnu"
```

### 8.4 检测使用了哪个库

```bash
# 方法 1：详细构建
cargo build --verbose 2>&1 | grep "libopus"

# 方法 2：检查 pkg-config
pkg-config --libs opus
# -L/.../vcpkg/installed/x64-linux/lib = vcpkg ✓
# -L/usr/lib/x86_64-linux-gnu = 系统 ✗

# 方法 3：检查 build.rs 输出
RUST_LOG=debug cargo build 2>&1 | grep opus

# 方法 4：构建后，检查依赖
ldd target/release/liblibrustdesk.so | grep opus
```

---

## 9. PIC 验证

### 9.1 检查什么

PIC 兼容性需要：
1. 使用 `-fPIC` 标志编译
2. 定义 `-DPIC` 宏（对于某些代码库）
3. 动态段中无 TEXTREL
4. 最少的绝对重定位（R_X86_64_32）

### 9.2 检查静态库（.a）

```bash
LIB=vcpkg/installed/x64-linux/lib/libopus.a

# 方法 1：检查 TEXTREL（仅限动态库）
# 对于 .a 文件，首先提取 .o：
mkdir /tmp/check-pic
cd /tmp/check-pic
ar -x "$LIB"
readelf -d *.o 2>/dev/null | grep TEXTREL
# 无输出 = 好

# 方法 2：检查重定位
readelf -r "$LIB" | grep "R_X86_64_32[^S]"
# 应该无或很少

# 方法 3：检查 objdump
objdump -r "$LIB" | grep "R_X86_64_32[^S]"
# 输出最少 = PIC

# 方法 4：检查 PIC 代码模式
objdump -d "$LIB" | grep "@PLT" | head -5
# 存在 @PLT（过程链接表）= PIC
```

**注意**：`R_X86_64_32S` 是可以的，`R_X86_64_32`（没有 S）是非 PIC。

### 9.3 检查共享库（.so）

```bash
LIB=target/release/liblibrustdesk.so

# 方法 1：检查 TEXTREL
readelf -d "$LIB" | grep TEXTREL
# 无输出 = PIC ✓
# 有 TEXTREL = 非 PIC ✗

# 方法 2：检查重定位
readelf -r "$LIB" | grep "R_X86_64_32[^S]"
# 应该无

# 方法 3：使用 file 检查
file "$LIB"
# 应该显示 "LSB shared object" 而不是 "LSB executable"
```

### 9.4 检查目标文件（.o）

```bash
OBJ=target/release/deps/rustdesk-abc123.o

# 检查重定位
readelf -r "$OBJ" | grep "R_X86_64_32[^S]"

# 检查符号
nm "$OBJ" | grep "U "  # 未定义符号
```

### 9.5 自动 PIC 检查脚本

```bash
#!/bin/bash
# check-pic.sh - 检查库是否符合 PIC

check_pic() {
    local file=$1
    local type=$(file "$file")

    echo "检查：$file"
    echo "类型：$type"

    if [[ "$type" == *"ar archive"* ]]; then
        # 静态库 - 提取并检查目标文件
        local tmpdir=$(mktemp -d)
        cd "$tmpdir"
        ar -x "$file"

        local non_pic=0
        for obj in *.o; do
            if readelf -r "$obj" 2>/dev/null | grep -q "R_X86_64_32[^S]"; then
                echo "  ✗ $obj：包含非 PIC 重定位"
                non_pic=1
            fi
        done

        cd - > /dev/null
        rm -rf "$tmpdir"

        if [ $non_pic -eq 0 ]; then
            echo "  ✓ PIC 兼容"
            return 0
        else
            echo "  ✗ 不符合 PIC"
            return 1
        fi

    elif [[ "$type" == *"shared object"* ]]; then
        # 共享库 - 检查 TEXTREL
        if readelf -d "$file" 2>/dev/null | grep -q TEXTREL; then
            echo "  ✗ 有 TEXTREL（非 PIC）"
            return 1
        else
            echo "  ✓ 无 TEXTREL（PIC）"
            return 0
        fi
    else
        echo "  ? 未知文件类型"
        return 2
    fi
}

# 使用方法
check_pic vcpkg/installed/x64-linux/lib/libopus.a
check_pic target/release/liblibrustdesk.so
```

### 9.6 修复非 PIC 库

如果库不是 PIC：

```bash
# 对于 vcpkg 库
cd vcpkg
rm -rf packages/PACKAGE_x64-linux
rm -rf buildtrees/PACKAGE
rm -rf installed/x64-linux/lib/libPACKAGE.*

# 使用覆盖端口用 PIC 重新构建
CFLAGS="-fPIC -DPIC" CXXFLAGS="-fPIC -DPIC" \
  ./vcpkg install PACKAGE:x64-linux --overlay-ports=../res/vcpkg/PACKAGE

# 对于系统库 - 使用 vcpkg 替代
# 无法修复系统库，必须使用 vcpkg 替换
```

---

## 10. 检查 .a 和 .o 文件

### 10.1 静态库（.a）结构

`.a` 文件是 `.o` 目标文件的归档：

```bash
# 列出内容
ar -t libopus.a
# 输出：
# opus_encoder.o
# opus_decoder.o
# opus_multistream.o
# ...

# 提取所有
ar -x libopus.a

# 提取特定文件
ar -x libopus.a opus_encoder.o
```

### 10.2 比较 .a 文件

检查两个库是否兼容：

```bash
# 检查架构
file lib1.a lib2.a
# 两者都应该是 "current ar archive" 和相同架构（x86-64）

# 比较符号
nm -g lib1.a | sort > lib1-symbols.txt
nm -g lib2.a | sort > lib2-symbols.txt
diff lib1-symbols.txt lib2-symbols.txt

# 检查 PIC 兼容性
readelf -r lib1.a | grep "R_X86_64_32[^S]" > lib1-reloc.txt
readelf -r lib2.a | grep "R_X86_64_32[^S]" > lib2-reloc.txt
```

### 10.3 检查 .o 文件

目标文件是编译后的单元：

```bash
# 获取文件信息
file opus_encoder.o
# 输出：ELF 64-bit LSB relocatable, x86-64

# 列出符号
nm opus_encoder.o
# T = 已定义文本（代码）
# U = 未定义（需要链接）
# D = 已定义数据

# 检查重定位
readelf -r opus_encoder.o

# 检查段
readelf -S opus_encoder.o
```

### 10.4 文件间匹配检查

验证目标文件是否匹配库：

```bash
# 提取库目标文件
ar -x libopus.a opus_encoder.o
mv opus_encoder.o opus_encoder_lib.o

# 与编译的目标文件比较
cmp opus_encoder_lib.o /path/to/compiled/opus_encoder.o
# 无输出 = 相同

# 比较符号
nm opus_encoder_lib.o | sort > lib-symbols.txt
nm /path/to/compiled/opus_encoder.o | sort > compiled-symbols.txt
diff lib-symbols.txt compiled-symbols.txt

# 检查 .o 文件是否在 .a 中
ar -t libopus.a | grep opus_encoder.o
```

### 10.5 综合库检查

```bash
#!/bin/bash
# full-library-check.sh - 完整库分析

LIB=$1
echo "=========================================="
echo "库分析：$LIB"
echo "=========================================="

# 1. 文件类型
echo -e "\n1. 文件类型"
file "$LIB"

# 2. 架构
echo -e "\n2. 架构"
readelf -h "$LIB" 2>/dev/null | grep "Class\|Machine" || ar -t "$LIB" | head -1 | xargs file

# 3. 内容（.a）
if [[ "$LIB" == *.a ]]; then
    echo -e "\n3. 归档内容（前 10 个）"
    ar -t "$LIB" | head -10
fi

# 4. 符号（前 20 个已定义）
echo -e "\n4. 已定义符号（前 20 个）"
nm -g "$LIB" | grep " T " | head -20

# 5. PIC 检查
echo -e "\n5. PIC 兼容性"
if [[ "$LIB" == *.a ]]; then
    tmpdir=$(mktemp -d)
    cd "$tmpdir"
    ar -x "$LIB"

    non_pic_count=0
    for obj in *.o; do
        if readelf -r "$obj" 2>/dev/null | grep -q "R_X86_64_32[^S]"; then
            ((non_pic_count++))
        fi
    done

    total=$(ls -1 *.o | wc -l)
    echo "目标文件：总共 $total 个，$non_pic_count 个非 PIC"

    if [ $non_pic_count -eq 0 ]; then
        echo "✓ 所有目标文件都符合 PIC"
    else
        echo "✗ $non_pic_count 个目标文件包含非 PIC 代码"
    fi

    cd - > /dev/null
    rm -rf "$tmpdir"

elif [[ "$LIB" == *.so ]]; then
    if readelf -d "$LIB" | grep -q TEXTREL; then
        echo "✗ 有 TEXTREL（非 PIC）"
    else
        echo "✓ 无 TEXTREL（PIC 兼容）"
    fi
fi

# 6. 依赖（.so）
if [[ "$LIB" == *.so ]]; then
    echo -e "\n6. 依赖"
    ldd "$LIB" 2>/dev/null || readelf -d "$LIB" | grep NEEDED
fi

# 7. 重定位示例
echo -e "\n7. 重定位（前 10 个）"
readelf -r "$LIB" 2>/dev/null | head -20 || echo "无重定位信息"

echo -e "\n=========================================="
echo "分析完成"
echo "=========================================="
```

使用方法：
```bash
bash full-library-check.sh vcpkg/installed/x64-linux/lib/libopus.a
bash full-library-check.sh target/release/liblibrustdesk.so
```

### 10.6 快速参考命令

```bash
# 提取并检查 .a 中所有目标文件的 PIC
ar -x libopus.a && for f in *.o; do echo "$f:"; readelf -r "$f" | grep -c "R_X86_64_32[^S]"; done

# 查找包含符号的 .a
for lib in vcpkg/installed/x64-linux/lib/*.a; do
    nm -A "$lib" | grep -q "opus_encode" && echo "$lib"
done

# 比较两个 .a 文件
diff <(ar -t lib1.a | sort) <(ar -t lib2.a | sort)

# 检查目录中所有 .o 文件的 PIC
find . -name "*.o" -exec sh -c 'readelf -r {} | grep -q "R_X86_64_32[^S]" && echo "{}: 非 PIC"' \;

# 从 .a 提取特定目标文件进行检查
ar -x libopus.a opus_encoder.o && nm opus_encoder.o | grep opus_encode
```

---

## 11. 实际案例：Ubuntu 18.04 PIC 问题

### 11.1 问题

```
error: could not compile `magnum-opus` (lib)
relocation R_X86_64_32 against `.rodata' can not be used when making a shared object
```

### 11.2 根本原因分析

```bash
# 步骤 1：识别哪个库
cargo build -vv 2>&1 | grep "libopus"
# 发现：使用 /usr/lib/x86_64-linux-gnu/libopus.a

# 步骤 2：检查系统库是否有 PIC
readelf -r /usr/lib/x86_64-linux-gnu/libopus.a | grep "R_X86_64_32[^S]"
# 输出：许多重定位 → 确认非 PIC

# 步骤 3：检查 vcpkg 库
readelf -r vcpkg/installed/x64-linux/lib/libopus.a | grep "R_X86_64_32[^S]"
# 输出：无 → PIC 兼容
```

### 11.3 解决步骤

```bash
# 1. 验证 vcpkg 库存在且为 PIC
bash full-library-check.sh vcpkg/installed/x64-linux/lib/libopus.a

# 2. 修复库搜索顺序
export LIBRARY_PATH="$VCPKG_INSTALLED/lib:/usr/lib/x86_64-linux-gnu"
export RUSTFLAGS="-L $VCPKG_INSTALLED/lib -L /usr/lib/x86_64-linux-gnu"

# 3. 修复 pkg-config 顺序（用于使用 pkg-config 的 build.rs）
export PKG_CONFIG_PATH="/usr/lib/x86_64-linux-gnu/pkgconfig:$VCPKG_INSTALLED/lib/pkgconfig"

# 4. 清理 cargo 缓存
rm -rf target/release/deps/libmagnum_opus*
rm -rf target/release/build/magnum-opus-*

# 5. 重新构建
cargo build --release

# 6. 验证成功
grep "libopus" build.log
# 应显示 vcpkg 路径，而不是系统路径
```

### 11.4 验证

```bash
# 检查最终二进制文件无 TEXTREL
readelf -d target/release/liblibrustdesk.so | grep TEXTREL
# 无输出 = 成功

# 检查依赖
ldd target/release/liblibrustdesk.so | grep opus
# 不应显示系统 libopus（静态链接）

# 验证 PIC
bash check-pic.sh target/release/liblibrustdesk.so
# 应输出：✓ 无 TEXTREL（PIC）
```

---

## 12. 故障排除检查清单

遇到链接问题时：

- [ ] 检查库搜索路径（`LIBRARY_PATH`、`LD_LIBRARY_PATH`、`RUSTFLAGS`）
- [ ] 检查头文件搜索路径（`C_INCLUDE_PATH`、`CPLUS_INCLUDE_PATH`、`CPATH`）
- [ ] 验证 pkg-config 路径（`PKG_CONFIG_PATH`）
- [ ] 确认库架构匹配（x86_64 vs x86，32 位 vs 64 位）
- [ ] 检查所有静态库的 PIC 兼容性
- [ ] 验证 vcpkg 库使用 `-fPIC -DPIC` 构建
- [ ] 确保 vcpkg 路径在所有搜索路径中排在最前面
- [ ] 修复依赖后清理 cargo 缓存
- [ ] 使用详细构建查看实际命令
- [ ] 检查实际使用的库（系统 vs vcpkg）
- [ ] 使用 `nm` 验证符号存在
- [ ] 使用 `readelf -r` 检查重定位
- [ ] 使用 `ldd` 测试库加载

---

## 13. 总结

### 核心原则

1. **搜索路径顺序很重要**：第一个路径获胜
2. **PIC 是必需的**：对于现代 Linux 上的共享库
3. **vcpkg 必须放在最前面**：以覆盖非 PIC 系统库
4. **更改后清理缓存**：Cargo 和 vcpkg 积极缓存
5. **验证，不要假设**：始终检查实际使用的库

### 基本命令

```bash
# 查找库
find /usr/lib /opt -name "libopus.*" 2>/dev/null

# 检查 PIC
readelf -d libfile.a | grep TEXTREL

# 检查符号
nm -g libfile.a | grep symbol_name

# 检查依赖
ldd binary

# 详细构建
cargo build -vv 2>&1 | tee build.log

# 检查 pkg-config
pkg-config --libs --cflags libname
```

### 快速诊断

| 症状 | 检查 | 修复 |
|------|------|------|
| 编译错误：找不到头文件 | `gcc -H -c test.c` | 添加到 `C_INCLUDE_PATH` |
| 链接错误：找不到 -lxxx | `find /usr/lib -name libxxx.*` | 添加到 `LIBRARY_PATH` |
| 链接错误：PIC 重定位 | `readelf -r libxxx.a \| grep R_X86_64_32` | 使用 `-fPIC -DPIC` 重新构建 |
| 运行时：找不到库 | `ldd binary` | 设置 `LD_LIBRARY_PATH` 或 RPATH |
| 使用了错误的库 | `cargo build -vv` | 修复路径顺序（vcpkg 优先） |

---

## 参考资料

- **vcpkg 文档**：https://vcpkg.io/
- **Rust 链接**：https://doc.rust-lang.org/rustc/linker-plugin-lto.html
- **位置无关代码**：https://wiki.gentoo.org/wiki/Hardened/Textrels_Guide
- **ELF 格式**：`man elf`
- **链接器**：`man ld`
- **pkg-config**：`man pkg-config`

---

**文档版本**：1.0
**最后更新**：2025-11-01
**基于**：RustDesk Ubuntu 18.04 构建经验
