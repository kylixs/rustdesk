#!/bin/bash

set -e

echo "========================================="
echo "Install gstreamer1.0-pipewire for Ubuntu"
echo "========================================="

# Check system version
echo "Checking system version..."
UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || echo "unknown")
UBUNTU_CODENAME=$(lsb_release -cs 2>/dev/null || echo "bionic")
echo "Ubuntu version: $UBUNTU_VERSION ($UBUNTU_CODENAME)"

# Manually add PPA
echo ""
echo "Manually adding PipeWire PPA (skip GPG verification)..."

# Create PPA source file
PPA_FILE="/etc/apt/sources.list.d/pipewire-debian-pipewire-upstream-$UBUNTU_CODENAME.list"
PPA_LINE="deb [trusted=yes] http://ppa.launchpad.net/pipewire-debian/pipewire-upstream/ubuntu $UBUNTU_CODENAME main"
PPA_SRC_LINE="# deb-src [trusted=yes] http://ppa.launchpad.net/pipewire-debian/pipewire-upstream/ubuntu $UBUNTU_CODENAME main"

echo "$PPA_LINE" | sudo tee "$PPA_FILE"
echo "$PPA_SRC_LINE" | sudo tee -a "$PPA_FILE"

echo "✓ PPA source file created (skip GPG verification): $PPA_FILE"

# Update package list
echo ""
echo "Updating APT package list..."
sudo apt update

# Install gstreamer1.0-pipewire
echo ""
echo "Installing PipeWire packages..."
sudo apt install -y pipewire pipewire-audio-client-libraries gstreamer1.0-pipewire \
    libgstreamer1.0-dev gir1.2-gstreamer-1.0  gstreamer1.0-gl gstreamer1.0-plugins-base \
    libgstreamer-gl1.0-0 libgstreamer-plugins-base1.0-0 libgstreamer-plugins-base1.0-dev  

echo ""
echo "✓ gstreamer1.0-pipewire installation completed!"
