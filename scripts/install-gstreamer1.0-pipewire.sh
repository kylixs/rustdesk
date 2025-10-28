#!/bin/bash

set -e

echo "Install gstreamer1.0-pipewire for Ubuntu 18.04"
echo "=================================="

# 检查系统版本
echo "检查系统版本..."
UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || echo "unknown")
UBUNTU_CODENAME=$(lsb_release -cs 2>/dev/null || echo "bionic")
echo "Ubuntu 版本: $UBUNTU_VERSION ($UBUNTU_CODENAME)"

# 手动添加 PPA
echo ""
echo "手动添加 PipeWire PPA（跳过 GPG 验证）..."

# 创建 PPA 源文件
PPA_FILE="/etc/apt/sources.list.d/pipewire-debian-pipewire-upstream-$UBUNTU_CODENAME.list"
PPA_LINE="deb [trusted=yes] http://ppa.launchpad.net/pipewire-debian/pipewire-upstream/ubuntu $UBUNTU_CODENAME main"
PPA_SRC_LINE="# deb-src [trusted=yes] http://ppa.launchpad.net/pipewire-debian/pipewire-upstream/ubuntu $UBUNTU_CODENAME main"

echo "$PPA_LINE" | sudo tee "$PPA_FILE"
echo "$PPA_SRC_LINE" | sudo tee -a "$PPA_FILE"

echo "✓ PPA 源文件已创建（跳过 GPG 验证）: $PPA_FILE"


# 更新包列表
echo ""
echo "更新 APT 包列表..."
sudo apt update

# install gstreamer1.0-pipewire
sudo apt install pipewire pipewire-audio-client-libraries gstreamer1.0-pipewire

