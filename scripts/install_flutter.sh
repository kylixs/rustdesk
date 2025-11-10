#!/bin/bash

set -e

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "安装 Flutter 到远程系统..."

# 环境变量
FLUTTER_VERSION="3.24.5"
FLUTTER_DIR="/opt/flutter"

# 检查是否已安装
if [ -d "$FLUTTER_DIR" ] && [ -f "$FLUTTER_DIR/bin/flutter" ]; then
    echo "Flutter 已安装在 $FLUTTER_DIR"
    $FLUTTER_DIR/bin/flutter --version
    exit 0
fi

echo "下载并安装 Flutter $FLUTTER_VERSION..."

# 创建目录
sudo mkdir -p /opt

# 下载 Flutter
cd /tmp
if [ ! -f "flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" ]; then
    wget https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz
fi

# 解压到 /opt
sudo tar xf flutter_linux_${FLUTTER_VERSION}-stable.tar.xz -C /opt/

# 设置权限
sudo chown -R root:root /opt/flutter
sudo chmod -R 755 /opt/flutter

# 添加到 PATH（临时）
export PATH="/opt/flutter/bin:$PATH"

# 运行 flutter doctor
echo "运行 flutter doctor..."
/opt/flutter/bin/flutter doctor -v

# 预缓存
echo "预缓存 Flutter..."
/opt/flutter/bin/flutter precache

# 应用补丁（如果需要）
echo "应用 Flutter 补丁..."
cd /opt/flutter
if [ -f "$PROJECT_ROOT/.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff" ]; then
    sudo git apply $PROJECT_ROOT/.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff || echo "补丁已应用或应用失败"
fi

echo "✓ Flutter $FLUTTER_VERSION 安装完成"
echo "Flutter 路径: $FLUTTER_DIR"
echo "添加到 PATH: export PATH=\"/opt/flutter/bin:\$PATH\""

# 清理下载文件
rm -f /tmp/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz
