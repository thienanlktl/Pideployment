#!/bin/bash
# AWS IoT Pub/Sub GUI - Complete Installation Script for Raspberry Pi
# This script installs all dependencies from scratch
# Run: chmod +x install_raspberrypi.sh && sudo ./install_raspberrypi.sh

echo "========================================"
echo "AWS IoT Pub/Sub GUI - Installation"
echo "Raspberry Pi - Complete Setup"
echo "========================================"
echo ""

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/venv"

# Update package list
echo "Updating package list..."
apt-get update -y
echo ""

# Install system dependencies
echo "Installing system dependencies..."
apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    build-essential \
    cmake \
    ninja-build \
    pkg-config \
    libssl-dev \
    libffi-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    libncurses5-dev \
    libncursesw5-dev \
    xz-utils \
    tk-dev \
    libxml2-dev \
    libxmlsec1-dev \
    liblzma-dev \
    git \
    x11-utils \
    xauth \
    libxcb-xinerama0 \
    libxcb-cursor0 \
    libxcb1-dev \
    libxcb-keysyms1-dev \
    libxcb-image0-dev \
    libxcb-shm0-dev \
    libxcb-icccm4-dev \
    libxcb-sync-dev \
    libxcb-xfixes0-dev \
    libxcb-shape0-dev \
    libxcb-randr0-dev \
    libxcb-render-util0-dev \
    libxcb-util-dev \
    libxcb-xinerama0-dev \
    libxcb-xkb-dev \
    libxkbcommon-dev \
    libxkbcommon-x11-dev \
    libfontconfig1-dev \
    libfreetype6-dev \
    libx11-dev \
    libxext-dev \
    libxfixes-dev \
    libxi-dev \
    libxrender-dev \
    libx11-xcb-dev \
    libxcb-glx0-dev \
    libgl1-mesa-dev \
    libglu1-mesa-dev \
    libegl1-mesa-dev \
    libgles2-mesa-dev \
    libdrm-dev \
    libxcomposite-dev \
    libxcursor-dev \
    libxdamage-dev \
    libxrandr-dev \
    libxss-dev \
    libasound2-dev \
    libpulse-dev \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    libgstreamer-plugins-bad1.0-dev \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-libav \
    libicu-dev \
    libharfbuzz-dev \
    libjpeg-dev \
    libpng-dev \
    libtiff-dev \
    libwebp-dev \
    qt6-base-dev \
    qt6-base-dev-tools \
    qt6-tools-dev \
    qt6-tools-dev-tools \
    libqt6core6 \
    libqt6gui6 \
    libqt6widgets6 \
    libqt6network6 \
    libqt6dbus6 \
    libqt6svg6 \
    libqt6svg6-dev \
    libqt6opengl6 \
    libqt6opengl6-dev \
    libqt6openglwidgets6 \
    libqt6qml6 \
    libqt6qmlmodels6 \
    libqt6qmlworkerscript6 \
    libqt6quick6 \
    libqt6quickwidgets6
echo ""

# Remove old venv if exists
if [ -d "$VENV_DIR" ]; then
    echo "Removing old virtual environment..."
    rm -rf "$VENV_DIR"
fi

# Create virtual environment
echo "Creating virtual environment..."
python3 -m venv "$VENV_DIR" --system-site-packages
echo ""

# Activate virtual environment
echo "Activating virtual environment..."
source "$VENV_DIR/bin/activate"
export PATH="$VENV_DIR/bin:$PATH"
echo ""

# Upgrade pip
echo "Upgrading pip..."
python -m pip install --upgrade pip setuptools wheel
echo ""

# Set environment variables for PyQt6
export QT_SELECT=qt6
export PKG_CONFIG_PATH=/usr/lib/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig

# Install Python packages
echo "Installing PyQt6 (this may take 30-60 minutes)..."
python -m pip install PyQt6
echo ""

echo "Installing AWS IoT SDK..."
python -m pip install awsiotsdk
echo ""

echo "Installing additional dependencies..."
python -m pip install awscrt cryptography python-dateutil
echo ""

# Deactivate venv
deactivate

echo "========================================"
echo "Installation Complete!"
echo "========================================"
echo ""
echo "Virtual environment location: $VENV_DIR"
echo ""
echo "Next steps:"
echo "1. Place your certificate files in the PublishDemo folder"
echo "2. Run: ./run_raspberrypi.sh"
echo ""
