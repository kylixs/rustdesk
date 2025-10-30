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
VCPKG_INSTALLED="$VCPKG_ROOT/installed/$VCPKG_TRIPLET"

# Prefer system libraries for GTK/X11, vcpkg for codecs
export PKG_CONFIG_PATH="/usr/lib/x86_64-linux-gnu/pkgconfig:$VCPKG_INSTALLED/lib/pkgconfig:$PKG_CONFIG_PATH"

# Set library paths for runtime linking
export LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:$VCPKG_INSTALLED/lib:$LIBRARY_PATH"
export LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:$VCPKG_INSTALLED/lib:$LD_LIBRARY_PATH"

# Append vcpkg include paths (compiler uses default paths first, then these)
export C_INCLUDE_PATH="$C_INCLUDE_PATH:$VCPKG_INSTALLED/include"
export CPLUS_INCLUDE_PATH="$CPLUS_INCLUDE_PATH:$VCPKG_INSTALLED/include"

# Source cargo environment if exists
if [ -f "$HOME/.cargo/env" ]; then
    source "$HOME/.cargo/env"
fi

# Add library paths for Rust linker (system first for GTK/X11)
export RUSTFLAGS="-L /usr/lib/x86_64-linux-gnu -L $VCPKG_INSTALLED/lib"

# Use system default compiler settings
unset CFLAGS
unset CXXFLAGS
export CC="gcc"
export CXX="g++"

# Test compiler setup
echo "测试编译器设置..."
echo '#include <stdlib.h>' | gcc -x c -E - > /dev/null 2>&1 && echo "✓ C 编译器正常" || echo "✗ C 编译器有问题"
echo '#include <cstdlib>' | g++ -x c++ -E - > /dev/null 2>&1 && echo "✓ C++ 编译器正常" || echo "✗ C++ 编译器有问题"

# Verify FFmpeg libraries
echo "验证 FFmpeg 库..."
pkg-config --exists libavcodec && echo "✓ libavcodec 可用" || echo "✗ libavcodec 不可用"


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
