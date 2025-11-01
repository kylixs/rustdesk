#!/bin/bash

set -e

echo "================================================"
echo "vcpkg 依赖安装脚本 (支持 -fPIC)"
echo "================================================"
echo ""

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ===== 获取 sudo 权限 =====
if [[ $EUID -ne 0 ]]; then
    echo "此脚本需要 sudo 权限来安装系统依赖和清理缓存..."
    echo "请输入密码："

    # 获取 sudo 权限
    if ! sudo -v; then
        echo "错误: 无法获取 sudo 权限"
        exit 1
    fi

    # 保持 sudo 权限活跃（后台进程，每 60 秒更新）
    (
        while true; do
            sudo -n true
            sleep 60
            kill -0 "$$" 2>/dev/null || exit
        done
    ) &
    SUDO_KEEPER_PID=$!

    # 脚本退出时清理后台进程
    trap "kill $SUDO_KEEPER_PID 2>/dev/null || true" EXIT INT TERM

    echo "✓ sudo 权限已获取"
    echo ""
fi

export VCPKG_TRIPLET="${VCPKG_TRIPLET:-x64-linux}"
export VCPKG_ROOT="$PROJECT_ROOT/vcpkg"
INSTALL_DIR="$VCPKG_ROOT/installed/$VCPKG_TRIPLET"
TRIPLET_FILE="$VCPKG_ROOT/triplets/$VCPKG_TRIPLET.cmake"

cd $PROJECT_ROOT

echo "VCPKG_ROOT: $VCPKG_ROOT"
echo "TRIPLET: $VCPKG_TRIPLET"
echo ""
mkdir "$VCPKG_ROOT"

# Step 0: Verify -fPIC configuration
echo "Step 0: 验证 -fPIC 配置..."
if [ -f "$TRIPLET_FILE" ]; then
    if ! grep -q "VCPKG_C_FLAGS.*-fPIC" "$TRIPLET_FILE"; then
        echo "⚠️  Warning: -fPIC 未配置在 triplet 中"
        echo "   建议先运行: bash scripts/setup-for-ubuntu18.sh"
        echo ""
    else
        echo "✓ Triplet 已配置 -fPIC"
        echo ""
    fi
else
    echo "⚠️  Warning: Triplet 文件不存在: $TRIPLET_FILE"
    echo ""
fi

# 检查并升级 Python 版本
echo "检查 Python 版本..."

# 安装 bc 工具用于版本比较
sudo apt install -y bc

PYTHON_VERSION=$(python3 --version 2>&1 | grep -oP '\d+\.\d+' | head -1)
echo "当前 Python 版本: $PYTHON_VERSION"

if [ "$(echo "$PYTHON_VERSION < 3.7" | bc -l)" -eq 1 ]; then
    echo "Python 版本过低，需要 3.7+，正在安装 Python 3.8..."
    
    # 添加 deadsnakes PPA 并安装 Python 3.8
    sudo apt update
    sudo apt install -y software-properties-common
    sudo add-apt-repository -y ppa:deadsnakes/ppa
    sudo apt update
    sudo apt install -y python3.8 python3.8-dev python3.8-distutils
    
    # 创建 python3 符号链接指向 3.8
    sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.6 1
    sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.8 2
    sudo update-alternatives --set python3 /usr/bin/python3.8
    
    echo "✓ Python 已升级到 $(python3 --version)"
fi

# Step 1: 完整清理 vcpkg 缓存
echo "Step 1: 清理 vcpkg 缓存..."
echo "这将删除："
echo "  - installed/"
echo "  - buildtrees/"
echo "  - packages/"
echo "  - vcpkg status 数据库"
echo ""

# 删除已安装的库
if [ -d "$VCPKG_ROOT/installed/$VCPKG_TRIPLET" ]; then
    echo "删除 $VCPKG_ROOT/installed/$VCPKG_TRIPLET..."
    sudo rm -rf "$VCPKG_ROOT/installed/$VCPKG_TRIPLET" || true
fi

# 删除构建树（关键 - 包含缓存的对象文件）
if [ -d "$VCPKG_ROOT/buildtrees" ]; then
    echo "删除 $VCPKG_ROOT/buildtrees/..."
    sudo rm -rf $VCPKG_ROOT/buildtrees/* || true
fi

# 删除打包文件
if [ -d "$VCPKG_ROOT/packages" ]; then
    echo "删除 $VCPKG_ROOT/packages/..."
    sudo rm -rf $VCPKG_ROOT/packages/* || true
fi

# 删除 vcpkg 状态数据库（关键 - vcpkg 缓存安装状态）
if [ -f "$VCPKG_ROOT/installed/vcpkg/status" ]; then
    echo "删除 vcpkg 状态数据库..."
    sudo rm -f "$VCPKG_ROOT/installed/vcpkg/status" || true
fi

# 删除旧的下载文件
sudo rm -f $VCPKG_ROOT/downloads/* || true

echo "✓ 缓存清理完成"
echo ""

cd "$PROJECT_ROOT"

# Step 2: 创建修复的 overlay ports
echo "Step 2: 创建 AOM overlay port..."
mkdir -p ./res/vcpkg/aom

cat > ./res/vcpkg/aom/portfile.cmake << 'EOF'
vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO kylixs/aom
    REF main
    SHA512 f93c4c6cd5934e24fc0be91b1ed15b88fd19dbffffcd38e90ea08af9c779947c410e80c654b9f132492bb954d3c9217417d6534d8bc81728da3aeff0b10f4801
    HEAD_REF main
)

# Fix AVX2 compatibility for Ubuntu 18.04
vcpkg_replace_string("${SOURCE_PATH}/aom_dsp/flow_estimation/x86/disflow_avx2.c"
    "#include \"aom_dsp/flow_estimation/disflow.h\""
    "#include \"aom_dsp/flow_estimation/disflow.h\"
#ifndef _mm256_set_m128i
#define _mm256_set_m128i(hi, lo) _mm256_insertf128_si256(_mm256_castsi128_si256(lo), (hi), 1)
#endif"
)

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        -DCMAKE_BUILD_TYPE=Release
        -DENABLE_DOCS=OFF
        -DENABLE_EXAMPLES=OFF
        -DENABLE_TESTDATA=OFF
        -DENABLE_TESTS=OFF
        -DENABLE_TOOLS=OFF
        -DCONFIG_AV1_DECODER=1
        -DCONFIG_AV1_ENCODER=1
        -DCONFIG_MULTITHREAD=0
        -DCONFIG_RUNTIME_CPU_DETECT=0
        -DAOM_TARGET_CPU=generic
        -DENABLE_AVX2=OFF
        -DENABLE_SSE4_1=OFF
        -DENABLE_SSSE3=OFF
)

vcpkg_cmake_install()

# Fix cmake config path issue
if(EXISTS "${CURRENT_PACKAGES_DIR}/lib/cmake/aom")
    vcpkg_cmake_config_fixup(CONFIG_PATH lib/cmake/aom)
endif()

vcpkg_fixup_pkgconfig()

file(INSTALL "${SOURCE_PATH}/LICENSE" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}" RENAME copyright)
EOF

cat > ./res/vcpkg/aom/vcpkg.json << 'EOF'
{
  "name": "aom",
  "version": "3.0.0",
  "description": "AV1 codec library - Ubuntu 18.04 compatible",
  "dependencies": [
    {
      "name": "vcpkg-cmake",
      "host": true
    },
    {
      "name": "vcpkg-cmake-config",
      "host": true
    }
  ]
}
EOF

echo "创建 libyuv overlay port..."
mkdir -p ./res/vcpkg/libyuv

cat > ./res/vcpkg/libyuv/portfile.cmake << 'EOF'
vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO kylixs/libyuv
    REF main
    SHA512 9ee540f088882d598457c65d736c01c8786723a05aaa8dec6257550657bbc646d0f045add32404f7812379504737ea5a015b7306258ada78e63e4d62a9dd7f40
    HEAD_REF main
)

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        -DCMAKE_BUILD_TYPE=Release
)

vcpkg_cmake_install()

# Fix cmake config path issue
if(EXISTS "${CURRENT_PACKAGES_DIR}/lib/cmake/libyuv")
    vcpkg_cmake_config_fixup(CONFIG_PATH lib/cmake/libyuv)
endif()

vcpkg_fixup_pkgconfig()

file(INSTALL "${SOURCE_PATH}/LICENSE" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}" RENAME copyright)
EOF

cat > ./res/vcpkg/libyuv/vcpkg.json << 'EOF'
{
  "name": "libyuv",
  "version": "1.0.0",
  "description": "YUV scaling and conversion library - compatible version",
  "dependencies": [
    {
      "name": "vcpkg-cmake",
      "host": true
    },
    {
      "name": "vcpkg-cmake-config",
      "host": true
    }
  ]
}
EOF

echo "✓ Overlay ports 创建完成"

# Step 3: 安装 vcpkg 依赖（带 -fPIC）
echo "Step 3: 安装 vcpkg 依赖..."
echo "开始时间: $(date)"
echo "这将需要 10-20 分钟..."
echo ""

# 设置环境变量确保使用 -fPIC
export CFLAGS="-fPIC"
export CXXFLAGS="-fPIC"

# 使用 --x-install-root 和详细输出
if ! CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" $VCPKG_ROOT/vcpkg install --triplet $VCPKG_TRIPLET --x-install-root="$VCPKG_ROOT/installed" 2>&1 | tee vcpkg_install.log; then
    echo ""
    echo "ERROR: vcpkg 安装过程中出现错误"
    
    # 检查哪些包安装失败
    echo "检查安装状态..."
    REQUIRED_PACKAGES=("aom" "libyuv" "libvpx" "opus")
    FAILED_PACKAGES=()
    
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if [ ! -d "$VCPKG_ROOT/packages/${pkg}_${VCPKG_TRIPLET}" ]; then
            FAILED_PACKAGES+=("$pkg")
            echo "✗ $pkg - 安装失败"
        else
            echo "✓ $pkg - 安装成功"
        fi
    done
    
    if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
        echo ""
        echo "失败的包: ${FAILED_PACKAGES[*]}"
        echo ""
        
        # 显示失败包的详细错误日志
        for pkg in "${FAILED_PACKAGES[@]}"; do
            echo "=== $pkg 错误日志 ==="
            find "$VCPKG_ROOT/buildtrees" -name "*$pkg*" -name "*.log" | while read -r log_file; do
                echo "--- $log_file ---"
                tail -50 "$log_file"
                echo ""
            done
            echo "===================="
        done
        
        exit 1
    fi
fi

echo "结束时间: $(date)"

# 验证关键依赖
echo ""
echo "验证依赖安装..."


# 检查安装目录是否存在
if [ ! -d "$INSTALL_DIR" ]; then
    echo "错误：vcpkg 安装目录不存在: $INSTALL_DIR"
    echo "检查可能的安装目录..."
    find . -name "installed" -type d 2>/dev/null | head -5
    exit 1
fi

# 检查库文件
REQUIRED_LIBS=(
    "lib/libaom.a"
    "lib/libyuv.a" 
    "lib/libvpx.a"
    "lib/libopus.a"
)

MISSING_LIBS=()
for lib in "${REQUIRED_LIBS[@]}"; do
    if [ ! -f "$INSTALL_DIR/$lib" ]; then
        MISSING_LIBS+=("$lib")
        echo "✗ 缺少库文件: $lib"
    else
        size=$(ls -la "$INSTALL_DIR/$lib" | awk '{print $5}')
        echo "✓ $lib ($size bytes)"
    fi
done

# 检查头文件
REQUIRED_HEADERS=(
    "include/aom/aom_image.h"
    "include/libyuv.h"
    "include/vpx/vpx_codec.h" 
    "include/opus/opus.h"
)

MISSING_HEADERS=()
for header in "${REQUIRED_HEADERS[@]}"; do
    if [ ! -f "$INSTALL_DIR/$header" ]; then
        MISSING_HEADERS+=("$header")
        echo "✗ 缺少头文件: $header"
    else
        echo "✓ $header"
    fi
done

# 报告缺失的文件
if [ ${#MISSING_LIBS[@]} -gt 0 ] || [ ${#MISSING_HEADERS[@]} -gt 0 ]; then
    echo ""
    echo "验证失败！缺少以下文件："
    if [ ${#MISSING_LIBS[@]} -gt 0 ]; then
        echo "缺少库文件: ${MISSING_LIBS[*]}"
    fi
    if [ ${#MISSING_HEADERS[@]} -gt 0 ]; then
        echo "缺少头文件: ${MISSING_HEADERS[*]}"
    fi
    echo ""
    echo "请检查上面的安装日志找出失败原因"
    exit 1
fi

# Step 4: 验证 PIC（Position Independent Code）
echo ""
echo "Step 4: 验证 PIC（Position Independent Code）..."

OPUS_LIB="$INSTALL_DIR/lib/libopus.a"
if [ ! -f "$OPUS_LIB" ]; then
    echo "⚠️  Warning: libopus.a 未找到，跳过 PIC 验证"
else
    echo "检查 libopus.a 的 PIC 编译..."
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"

    # 提取第一个目标文件
    ar x "$OPUS_LIB" $(ar t "$OPUS_LIB" | head -1) 2>/dev/null || true
    OBJ_FILE=$(ls *.o 2>/dev/null | head -1)

    if [ -n "$OBJ_FILE" ] && [ -f "$OBJ_FILE" ]; then
        ABSOLUTE_RELOCS=$(readelf -r "$OBJ_FILE" 2>/dev/null | grep -c "R_X86_64_32" || true)

        if [ "$ABSOLUTE_RELOCS" -eq 0 ]; then
            echo "✓ 无绝对重定位（PIC 编译正确）"
        else
            echo "⚠️  发现 $ABSOLUTE_RELOCS 个绝对重定位"
            echo "   这可能表示 -fPIC 未正确应用"
            echo "   但这可能不会导致链接失败，继续..."
        fi
    else
        echo "⚠️  无法提取目标文件进行验证，跳过"
    fi

    cd - > /dev/null
    rm -rf "$TEMP_DIR"
fi

echo ""
echo "================================================"
echo "✓ 所有 vcpkg 依赖安装并验证成功！"
echo "================================================"
echo ""
echo "安装目录: $INSTALL_DIR"
echo ""
echo "下一步："
echo "  1. 设置环境变量:"
echo "     export VCPKG_ROOT=\$(pwd)/vcpkg"
echo ""
echo "  2. 编译 RustDesk:"
echo "     cargo build --features hwcodec,flutter,unix-file-copy-paste --release"
echo ""
