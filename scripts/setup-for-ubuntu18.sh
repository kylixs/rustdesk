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
apt-get update -y
apt-get install -y software-properties-common

#add-apt-repository -y ppa:jonathonf/ffmpeg-4
# Add the PPA manually
echo "deb [trusted=yes] http://ppa.launchpad.net/jonathonf/ffmpeg-4/ubuntu bionic main" | sudo tee /etc/apt/sources.list.d/ffmpeg-4.list
echo "# deb-src [trusted=yes] http://ppa.launchpad.net/jonathonf/ffmpeg-4/ubuntu bionic main" | sudo tee -a /etc/apt/sources.list.d/ffmpeg-4.list


apt-get update -y

apt-get install -y \
    curl wget git build-essential libc6-dev \
    pkg-config cmake ninja-build \
    nasm yasm \
    libstdc++-7-dev g++ \
    libgtk-3-dev clang \
    libxcb-randr0-dev libxdo-dev \
    libxfixes-dev libxcb-shape0-dev libxcb-xfixes0-dev \
    libasound2-dev libpulse-dev \
    libclang-dev \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
    libpam0g-dev libva-dev \
    zip unzip \
    ffmpeg libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libavfilter-dev \
    libopus-dev libvpx-dev

echo "✓ Essential tools installed"

# Fix xfixes.pc fixesproto version requirement (Ubuntu 18.04 compatibility)
# xfixes.pc requires fixesproto >= 6.0, but Ubuntu 18.04 only has 5.0
# Remove the version constraint to allow building
echo "Patching xfixes.pc for Ubuntu 18.04 compatibility..."
if [ -f /usr/lib/x86_64-linux-gnu/pkgconfig/xfixes.pc ]; then
    sed -i 's/fixesproto >= 6.0/fixesproto/g' /usr/lib/x86_64-linux-gnu/pkgconfig/xfixes.pc
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

source $HOME/.cargo/env
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
# Change library type to cdylib only
sed -i 's/\["cdylib", "staticlib", "rlib"\]/["cdylib"]/g' Cargo.toml
# Fix library name to avoid lib prefix duplication (librustdesk -> rustdesk)
sed -i 's/name = "librustdesk"/name = "rustdesk"/g' Cargo.toml
echo "✓ Cargo.toml configured (cdylib only, correct lib name)"

# Step 5: Setup vcpkg
echo ""
echo "Step 5: Setting up vcpkg..."
export VCPKG_ROOT="$PROJECT_ROOT/vcpkg"
VCPKG_INSTALLED="$VCPKG_ROOT/installed/$VCPKG_TRIPLET"

if [ ! -d "$VCPKG_ROOT" ]; then
    cd $PROJECT_ROOT
    sudo git clone https://github.com/Microsoft/vcpkg.git
    cd vcpkg
    sudo git checkout $VCPKG_COMMIT_ID
    sudo ./bootstrap-vcpkg.sh
    sudo chmod -R 755 $VCPKG_ROOT
else
    echo "vcpkg already exists at $VCPKG_ROOT"
fi

echo "✓ vcpkg ready: $(cd $VCPKG_ROOT && git rev-parse --short HEAD)"

# Step 6: Install vcpkg dependencies
echo ""
echo "Step 6: Installing vcpkg dependencies..."
echo "This will take n minutes..."

cd "$PROJECT_ROOT"

# Clean any previous failed builds
rm -rf $VCPKG_ROOT/installed || true
rm -rf $VCPKG_ROOT/buildtrees/aom* || true
rm -rf $VCPKG_ROOT/packages/aom* || true
rm -rf $VCPKG_ROOT/buildtrees/libyuv* || true
rm -rf $VCPKG_ROOT/packages/libyuv* || true

if ! $VCPKG_ROOT/vcpkg install --triplet $VCPKG_TRIPLET --x-install-root="$VCPKG_ROOT/installed"; then
    echo "ERROR: vcpkg installation failed"
    find "${VCPKG_ROOT}/" -name "*.log" | while read -r _1; do
        echo "$_1:"
        echo "======"
        cat "$_1"
        echo "======"
        echo ""
    done
    exit 1
fi

# Verify critical dependencies are installed correctly
echo ""
echo "Verifying vcpkg dependencies..."

# Check critical libraries (vcpkg would have failed if these weren't installed)
for lib in aom yuv vpx opus; do
    if [ ! -f "$VCPKG_INSTALLED/lib/lib${lib}.a" ]; then
        echo "ERROR: lib${lib}.a not found. vcpkg installation may have issues."
        exit 1
    fi
done

echo "✓ Critical dependencies verified: libaom, libyuv, libvpx, libopus"
[ -f "$VCPKG_INSTALLED/include/libavutil/attributes.h" ] && echo "  FFmpeg: vcpkg" || echo "  FFmpeg: system ($(ffmpeg -version 2>/dev/null | head -1 | awk '{print $3}'))"
echo "✓ vcpkg dependencies installed"

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
echo "  1. Run: ./build.sh"
echo ""
