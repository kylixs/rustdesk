#!/bin/bash

set -e

echo "统一 vcpkg 依赖安装脚本"
echo "========================"

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export VCPKG_TRIPLET="x64-linux"
export VCPKG_ROOT="$PROJECT_ROOT/vcpkg"
INSTALL_DIR="$VCPKG_ROOT/installed/$VCPKG_TRIPLET"

cd $PROJECT_ROOT

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

# 清理之前的安装和下载
echo "清理之前的安装..."
sudo rm -rf $VCPKG_ROOT/installed || true
sudo rm -rf $VCPKG_ROOT/buildtrees || true
sudo rm -rf $VCPKG_ROOT/packages || true
sudo rm -f $VCPKG_ROOT/downloads/kylixs-*.tar.gz || true

# 创建修复的 AOM overlay port
echo "创建 AOM overlay port..."
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

# 创建修复的 libyuv overlay port
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

# 安装依赖
echo "安装 vcpkg 依赖..."
echo "开始时间: $(date)"

# 使用 --x-install-root 和详细输出
if ! sudo $VCPKG_ROOT/vcpkg install --triplet $VCPKG_TRIPLET --x-install-root="$VCPKG_ROOT/installed" 2>&1 | tee vcpkg_install.log; then
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

echo ""
echo "✓ 所有 vcpkg 依赖安装并验证成功！"
echo "安装目录: $INSTALL_DIR"
echo ""
echo "现在可以编译 RustDesk："
echo "export VCPKG_ROOT=\$(pwd)/vcpkg"
echo "cargo build --release"
