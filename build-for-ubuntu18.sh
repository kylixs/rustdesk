#!/bin/bash
set -e

# RustDesk CI-based Build Script
# Strictly follows .github/workflows/flutter-build.yml build-rustdesk-linux Docker run section

echo "==========================================="
echo "RustDesk CI Build Script (x86_64)"
echo "==========================================="

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT=$SCRIPT_DIR 

# Environment setup
export RUST_VERSION="1.75"
export FLUTTER_VERSION="3.24.5"
export VERSION="1.4.2"
export TARGET="x86_64-unknown-linux-gnu"
export VCPKG_TRIPLET="x64-linux"
export DEB_ARCH="amd64"
export ARCH="x86_64"
export JOBS=""  # empty for x86_64, "--jobs 3" for aarch64

export VCPKG_ROOT="$PROJECT_ROOT/vcpkg"
export VCPKG_INSTALLED="$VCPKG_ROOT/installed/$VCPKG_TRIPLET"

# Prefer system libraries for GTK/X11, vcpkg for codecs
export PKG_CONFIG_PATH="/usr/lib/x86_64-linux-gnu/pkgconfig:$VCPKG_INSTALLED/lib/pkgconfig:$PKG_CONFIG_PATH"

# Set library paths for runtime linking
# IMPORTANT: vcpkg libs FIRST to override system libs (system libs don't have PIC)
export LIBRARY_PATH="$VCPKG_INSTALLED/lib:/usr/lib/x86_64-linux-gnu:$LIBRARY_PATH"
export LD_LIBRARY_PATH="$VCPKG_INSTALLED/lib:/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"

# Append vcpkg include paths (compiler uses default paths first, then these)
export C_INCLUDE_PATH="$C_INCLUDE_PATH:$VCPKG_INSTALLED/include"
export CPLUS_INCLUDE_PATH="$CPLUS_INCLUDE_PATH:$VCPKG_INSTALLED/include"

# Source cargo environment if exists
if [ -f "$HOME/.cargo/env" ]; then
    source "$HOME/.cargo/env"
fi

# Add library paths for Rust linker (vcpkg first to override system libs without PIC)
export RUSTFLAGS="-L $VCPKG_INSTALLED/lib -L /usr/lib/x86_64-linux-gnu"

# Set compiler flags for PIC (required for shared library linking, especially for hwcodec FFmpeg)
export CFLAGS="-fPIC"
export CXXFLAGS="-fPIC"
export ASFLAGS="-fPIC"
# Target-specific flags for cc crate (underscores instead of hyphens)
#export CFLAGS_x86_64_unknown_linux_gnu="-fPIC"
#export CXXFLAGS_x86_64_unknown_linux_gnu="-fPIC"
export CC="gcc"
export CXX="g++"

# Test compiler setup
echo "测试编译器设置..."
echo '#include <stdlib.h>' | gcc -x c -E - > /dev/null 2>&1 && echo "✓ C 编译器正常" || echo "✗ C 编译器有问题"
echo '#include <cstdlib>' | g++ -x c++ -E - > /dev/null 2>&1 && echo "✓ C++ 编译器正常" || echo "✗ C++ 编译器有问题"

# Verify FFmpeg libraries
echo "验证 FFmpeg 库..."
pkg-config --exists libavcodec && echo "✓ libavcodec 可用" || echo "✗ libavcodec 不可用"

# Configure libclang for ffigen (ffigen 8.0+ requires libclang 10+)
echo "配置 ffigen 所需的 libclang..."
if [ -f "/usr/lib/x86_64-linux-gnu/libclang-10.so.1" ]; then
    export LIBCLANG_PATH=/usr/lib/x86_64-linux-gnu
    export CPATH=/usr/lib/llvm-10/include:/usr/include:$CPATH
    export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH
    echo "✓ libclang-10 已配置"
else
    echo "✗ 警告: libclang-10 未安装，ffigen 可能会失败"
    echo "  请运行: sudo bash scripts/fix-ffigen-libclang.sh"
fi


cd "$PROJECT_ROOT"
WORKSPACE=$(pwd)

echo "Workspace: $WORKSPACE"
echo "VCPKG_ROOT: $VCPKG_ROOT"
echo ""

# Verify Rust installation
RUST_TOOLCHAIN_VERSION=$(cargo --version | awk '{print $2}')
echo "Rust version: $RUST_TOOLCHAIN_VERSION"

# Step 1: Generate Flutter Rust Bridge (if not exists)
echo ""
echo "Step 1: Generating Flutter Rust Bridge..."
cd $WORKSPACE
./scripts/generate_bridge.sh

# Step 2: Build Rust library
echo ""
echo "Step 2: Building Rust library..."
cd $WORKSPACE
./scripts/rust_build.sh

# Step 3: Build Flutter application and packages
echo ""
echo "Step 3: Building Flutter application and packages..."
cd $WORKSPACE
./scripts/flutter_build.sh
