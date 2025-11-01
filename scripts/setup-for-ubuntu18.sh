#!/bin/bash
set -e

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# RustDesk CI-based Environment Setup Script for Docker Ubuntu 18.04

echo "==========================================="
echo "RustDesk CI Environment Setup (x86_64)"
echo "Docker Ubuntu 18.04 Environment"
echo "==========================================="
echo ""

# ===== 获取 sudo 权限 =====
if [[ $EUID -ne 0 ]]; then
    echo "此脚本需要 sudo 权限来安装系统依赖..."
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

# Environment Variables (from CI)
export RUST_VERSION="1.75"
export FLUTTER_VERSION="3.24.5"
export VCPKG_COMMIT_ID="120deac3062162151622ca4860575a33844ba10b"
export VERSION="1.4.2"
export TARGET="x86_64-unknown-linux-gnu"
export VCPKG_TRIPLET="x64-linux"
export DEB_ARCH="amd64"
export ARCH="x86_64"

echo "Project root: $PROJECT_ROOT"
echo "Target: $TARGET"
echo "Architecture: $ARCH"
echo "Working directory: $(pwd)"
echo ""

# Step 1: Update package lists and install essential tools
echo "Step 1: Installing essential tools for Ubuntu 18.04..."

# Add FFmpeg 4.x PPA for Ubuntu 18.04
sudo apt-get update -y
sudo apt-get install -y software-properties-common

#add-apt-repository -y ppa:jonathonf/ffmpeg-4
# Add the PPA manually
echo "deb [trusted=yes] http://ppa.launchpad.net/jonathonf/ffmpeg-4/ubuntu bionic main" | sudo tee /etc/apt/sources.list.d/ffmpeg-4.list
echo "# deb-src [trusted=yes] http://ppa.launchpad.net/jonathonf/ffmpeg-4/ubuntu bionic main" | sudo tee -a /etc/apt/sources.list.d/ffmpeg-4.list


sudo apt-get update -y

sudo apt-get install -y \
    curl wget git build-essential libc6-dev \
    pkg-config cmake ninja-build \
    nasm yasm \
    libstdc++-7-dev g++ \
    libgtk-3-dev clang \
    libxcb-randr0-dev libxdo-dev \
    libxfixes-dev libxcb-shape0-dev libxcb-xfixes0-dev \
    libasound2-dev libpulse-dev \
    libclang-10-dev llvm-10-dev \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
    libpam0g-dev libva-dev \
    zip unzip \
    ffmpeg libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libavfilter-dev \
    libopus-dev libvpx-dev

echo "✓ Essential tools installed"

# Create symlink for ffigen to find libclang-10 (ffigen 8.0+ requires libclang 10+)
echo ""
echo "Configuring libclang-10 for ffigen..."
if [ -f "/usr/lib/x86_64-linux-gnu/libclang-10.so.1" ]; then
    if [ ! -L "/usr/lib/llvm-10/lib/libclang.so" ]; then
        sudo ln -sf /usr/lib/x86_64-linux-gnu/libclang-10.so.1 /usr/lib/llvm-10/lib/libclang.so
        echo "✓ Created libclang.so symlink for ffigen"
    else
        echo "✓ libclang.so symlink already exists"
    fi
else
    echo "⚠️  Warning: libclang-10 not found"
fi

# Fix xfixes.pc fixesproto version requirement (Ubuntu 18.04 compatibility)
# xfixes.pc requires fixesproto >= 6.0, but Ubuntu 18.04 only has 5.0
# Remove the version constraint to allow building
echo "Patching xfixes.pc for Ubuntu 18.04 compatibility..."
if [ -f /usr/lib/x86_64-linux-gnu/pkgconfig/xfixes.pc ]; then
    sudo sed -i 's/fixesproto >= 6.0/fixesproto/g' /usr/lib/x86_64-linux-gnu/pkgconfig/xfixes.pc
    echo "✓ xfixes.pc patched (removed fixesproto version constraint)"
fi

# Fix libstdc++.so symlink for clang linker
if [ ! -f /usr/lib/x86_64-linux-gnu/libstdc++.so ]; then
    sudo ln -sf /usr/lib/x86_64-linux-gnu/libstdc++.so.6 /usr/lib/x86_64-linux-gnu/libstdc++.so
    echo "✓ Created libstdc++.so symlink"
fi

# Step 2: Initialize git submodules
echo ""
echo "Step 2: Initializing git submodules..."
cd "$PROJECT_ROOT"

# Fix git ownership issue in Docker
git config --global --add safe.directory "$PROJECT_ROOT"
git config --global --add safe.directory '*'

git submodule update --init --recursive
echo "✓ Git submodules initialized"

# Step 3: Install Rust toolchain
echo ""
echo "Step 3: Installing Rust $RUST_VERSION..."
if ! command -v rustc &> /dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain $RUST_VERSION
fi

. $HOME/.cargo/env
rustup toolchain install $RUST_VERSION
rustup default $RUST_VERSION
rustup target add $TARGET
rustup component add rustfmt

# Save Rust toolchain version
RUST_TOOLCHAIN_VERSION=$(cargo --version | awk '{print $2}')
echo "RUST_TOOLCHAIN_VERSION=$RUST_TOOLCHAIN_VERSION"
export RUST_TOOLCHAIN_VERSION

echo "✓ Rust installed: rustc $(rustc --version)"

# Step 4: Configure Cargo.toml
echo ""
echo "Step 4: Configuring Cargo.toml..."
cd "$PROJECT_ROOT"

# Check if crate-type is set to ["cdylib"] for shared library only
# We only need cdylib (shared library), not rlib, for Flutter integration
CRATE_TYPE_LINE=$(grep -E '^\s*crate-type\s*=' Cargo.toml || echo "")
if [ -n "$CRATE_TYPE_LINE" ]; then
    if echo "$CRATE_TYPE_LINE" | grep -qE 'crate-type\s*=\s*\["cdylib"\]'; then
        echo "✓ Cargo.toml already configured with cdylib only (shared library)"
    else
        echo "Configuring Cargo.toml: setting crate-type = [\"cdylib\"] (shared library only)"
        echo "  This simplifies build and reduces compilation time"
        # Replace crate-type line with the correct configuration
        sed -i 's/^\s*crate-type\s*=.*$/crate-type = ["cdylib"]/' Cargo.toml
        echo "✓ Cargo.toml configured for shared library build"
    fi
else
    echo "⚠️  Warning: Could not find crate-type in Cargo.toml"
fi

# Step 5: Setup vcpkg
echo ""
echo "Step 5: Setting up vcpkg..."
echo " Calling setup-vcpkg-for-ubuntu18.sh .."
echo ""

cd "$PROJECT_ROOT"
export VCPKG_ROOT="$PROJECT_ROOT/vcpkg"
if ! bash "$SCRIPT_DIR/setup-vcpkg-for-ubuntu18.sh"; then
    echo ""
    echo "ERROR: setup vcpkg failed"
    exit 1
fi

# Step 6: Install vcpkg dependencies
echo ""
echo "Step 6: Installing vcpkg dependencies..."
echo "Calling install-vcpkg-for-ubuntu18.sh..."
echo ""

cd "$PROJECT_ROOT"

# Call the dedicated vcpkg installation script
if ! bash "$SCRIPT_DIR/install-vcpkg-for-ubuntu18.sh"; then
    echo ""
    echo "ERROR: vcpkg installation failed"
    echo "Please check the error messages above"
    exit 1
fi

echo ""
echo "✓ vcpkg dependencies installed successfully"

# Step 7: Setup Flutter
echo ""
echo "Step 7: Setting up Flutter..."
export FLUTTER_DIR="/opt/flutter"
export PATH=$FLUTTER_DIR/bin:$PATH

if [ ! -d "$FLUTTER_DIR" ]; then
    echo "Downloading Flutter $FLUTTER_VERSION..."
    cd /tmp
    wget https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz
    tar xf flutter_linux_${FLUTTER_VERSION}-stable.tar.xz
    sudo mv flutter /opt/flutter
    sudo chmod -R 755 /opt/flutter
    rm flutter_linux_${FLUTTER_VERSION}-stable.tar.xz
else
    echo "Flutter already exists at $FLUTTER_DIR"
fi

# Run flutter doctor
echo "Running flutter doctor..."
cd "$PROJECT_ROOT"
flutter doctor -v

echo "✓ Flutter installed: $(flutter --version | head -1)"

echo ""
echo "==========================================="
echo "Environment Setup Complete!"
echo "==========================================="
echo ""
echo "Environment variables set:"
echo "  VCPKG_ROOT=$VCPKG_ROOT"
echo "  FLUTTER_DIR=$FLUTTER_DIR"
echo "  PATH includes Flutter and Cargo"
echo ""
echo "Next steps:"
echo "  1. Run: ./build-for-ubuntu18.sh"
echo ""
