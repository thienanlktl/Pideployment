#!/bin/bash
# AWS IoT Pub/Sub GUI - User Installation Script for Raspberry Pi
# This script installs all dependencies to user space (no sudo required)
# Run: chmod +x install_raspberrypi_user.sh && ./install_raspberrypi_user.sh

set -e  # Exit on any error

echo "========================================"
echo "AWS IoT Pub/Sub GUI - User Installation"
echo "Raspberry Pi - User Space Setup"
echo "========================================"
echo ""

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo "ERROR: Python 3 is not installed"
    echo "Please install Python 3 first:"
    echo "  sudo apt-get update && sudo apt-get install -y python3 python3-pip"
    exit 1
fi

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/venv"

# Warn about system dependencies
echo "NOTE: This script installs Python packages to a virtual environment."
echo "For PyQt6 to work properly, you may need system dependencies."
echo "If PyQt6 installation fails, run the full installation script:"
echo "  sudo ./install_raspberrypi.sh"
echo ""
read -p "Continue with user-space installation? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi
echo ""

# Create virtual environment
echo "Step 1: Creating virtual environment..."
if [ -d "$VENV_DIR" ]; then
    echo "⚠ Virtual environment already exists, removing old one..."
    rm -rf "$VENV_DIR"
fi

python3 -m venv "$VENV_DIR"
if [ $? -ne 0 ]; then
    echo "✗ Failed to create virtual environment"
    echo "Make sure python3-venv is installed:"
    echo "  sudo apt-get install -y python3-venv"
    exit 1
fi
echo "✓ Virtual environment created at: $VENV_DIR"
echo ""

# Activate virtual environment
echo "Activating virtual environment..."
source "$VENV_DIR/bin/activate"
if [ $? -ne 0 ]; then
    echo "✗ Failed to activate virtual environment"
    exit 1
fi
echo "✓ Virtual environment activated"
echo ""

# Upgrade pip in venv
echo "Step 2: Upgrading pip in virtual environment..."
python -m pip install --upgrade pip setuptools wheel
echo "✓ pip upgraded"
echo ""

# Install Python packages in venv
echo "Step 3: Installing Python packages in virtual environment..."

# Install PyQt6
echo "Installing PyQt6 (this may take 30-60 minutes on Raspberry Pi)..."
echo "Note: pip will use pre-built wheels if available (fast),"
echo "      otherwise it will build from source (30-60 minutes)"
echo ""

# Set environment variables for PyQt6 build
export QT_SELECT=qt6
export PKG_CONFIG_PATH=/usr/lib/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig

# Try to install PyQt6
python -m pip install PyQt6 || {
    echo "⚠ PyQt6 installation encountered issues"
    echo "This may be due to missing system dependencies."
    echo "Try running: sudo ./install_raspberrypi.sh"
    echo "Or install system packages manually:"
    echo "  sudo apt-get install -y qt6-base-dev libqt6gui6 libqt6widgets6"
    deactivate
    exit 1
}
echo "✓ PyQt6 installed"

# Install AWS IoT SDK
echo "Installing AWS IoT SDK..."
python -m pip install awsiotsdk
echo "✓ AWS IoT SDK installed"

# Install additional dependencies
echo "Installing additional dependencies..."
python -m pip install \
    awscrt \
    cryptography \
    python-dateutil
echo "✓ Additional dependencies installed"
echo ""

# Verify installations
echo "Step 4: Verifying installations in virtual environment..."
echo ""

# Check Python in venv
if python -c "import sys; print(sys.version)" &> /dev/null; then
    PYTHON_VERSION=$(python --version)
    PYTHON_PATH=$(which python)
    echo "✓ Python: $PYTHON_VERSION"
    echo "  Location: $PYTHON_PATH"
else
    echo "✗ Python not found in virtual environment"
    exit 1
fi

# Check pip in venv
if python -m pip --version &> /dev/null; then
    PIP_VERSION=$(python -m pip --version | cut -d' ' -f2)
    echo "✓ pip: $PIP_VERSION"
else
    echo "✗ pip not found in virtual environment"
    exit 1
fi

# Check PyQt6
if python -c "import PyQt6; print(PyQt6.__version__)" 2>/dev/null; then
    PYQT6_VERSION=$(python -c "import PyQt6; print(PyQt6.__version__)")
    echo "✓ PyQt6: $PYQT6_VERSION"
else
    echo "✗ PyQt6 not properly installed"
    exit 1
fi

# Check AWS IoT SDK
if python -c "import awsiot" 2>/dev/null; then
    echo "✓ AWS IoT SDK: Installed"
else
    echo "✗ AWS IoT SDK not properly installed"
    exit 1
fi

# Deactivate venv
deactivate

echo ""
echo "========================================"
echo "Installation Complete!"
echo "========================================"
echo ""
echo "All dependencies have been installed in the virtual environment."
echo "Virtual environment location: $VENV_DIR"
echo ""
echo "IMPORTANT: The 'venv' folder contains all Python dependencies."
echo "This folder will persist after reboot and can be moved with the project."
echo ""
echo "Next steps:"
echo "1. Make sure your certificate files are in the PublishDemo folder:"
echo "   - AmazonRootCA1.pem"
echo "   - ebb0b9fb27d1eb1ca52f7f89260e123a992759bf3b630f9863575015132ebbef-certificate.pem.crt"
echo "   - ebb0b9fb27d1eb1ca52f7f89260e123a992759bf3b630f9863575015132ebbef-private.pem.key"
echo ""
echo "2. Run the application (launcher scripts will activate venv automatically):"
echo "   chmod +x run_raspberrypi.sh"
echo "   ./run_raspberrypi.sh"
echo ""
echo "   Or use the simple launcher:"
echo "   chmod +x run_pi_simple.sh"
echo "   ./run_pi_simple.sh"
echo ""
echo "3. If running via SSH with GUI:"
echo "   ssh -X pi@raspberrypi-ip"
echo ""
echo "4. To manually activate the virtual environment:"
echo "   source venv/bin/activate"
echo ""

