#!/bin/bash
set -e
cd /data/work/projects/rustdesk-ubuntu18

echo "清除所有构建缓存..."
echo "======================================"

# 1. 清除 Rust target 目录
echo "1. 清除 target/ 目录..."
rm -rf target/
echo "✓ target/ 已清除"

# 2. 清除 hwcodec git checkout 缓存
echo ""
echo "2. 清除 hwcodec git checkout 缓存..."
rm -rf ~/.cargo/git/checkouts/hwcodec-*
echo "✓ hwcodec git 缓存已清除"

# 3. 清除 Cargo 注册表缓存（仅二进制文件）
echo ""
echo "3. 清除 Cargo 编译缓存..."
rm -rf ~/.cargo/registry/cache/
rm -rf ~/.cargo/registry/src/
echo "✓ Cargo 注册表缓存已清除"

echo ""
echo "======================================"
echo "所有缓存已清除完成！"
echo ""
