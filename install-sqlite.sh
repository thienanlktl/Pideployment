#!/bin/bash
# Script to install SQLite on Linux systems
# Supports Ubuntu/Debian, CentOS/RHEL, and Arch Linux

set -e

echo "=========================================="
echo "SQLite Installation Script"
echo "=========================================="

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_VERSION=$VERSION_ID
else
    echo "ERROR: Cannot detect OS. This script supports Ubuntu/Debian, CentOS/RHEL, and Arch Linux."
    exit 1
fi

echo "Detected OS: $OS"
echo "OS Version: $OS_VERSION"
echo ""

# Check if SQLite is already installed
if command -v sqlite3 &> /dev/null; then
    SQLITE_VERSION=$(sqlite3 --version | awk '{print $1}')
    echo "SQLite is already installed: version $SQLITE_VERSION"
    echo "Checking if Python sqlite3 module is available..."
    
    # Check Python sqlite3 module
    if python3 -c "import sqlite3" 2>/dev/null; then
        echo "✓ Python sqlite3 module is available"
        echo ""
        echo "SQLite installation is complete and ready to use!"
        exit 0
    else
        echo "WARNING: SQLite command-line tool is installed but Python sqlite3 module is not available"
        echo "This is unusual - Python should have sqlite3 built-in"
    fi
else
    echo "SQLite is not installed. Installing now..."
    echo ""
fi

# Install SQLite based on OS
case $OS in
    ubuntu|debian)
        echo "Installing SQLite on Ubuntu/Debian..."
        sudo apt-get update
        sudo apt-get install -y sqlite3 libsqlite3-dev
        ;;
    centos|rhel|fedora|rocky|almalinux)
        echo "Installing SQLite on CentOS/RHEL/Fedora..."
        if command -v dnf &> /dev/null; then
            sudo dnf install -y sqlite sqlite-devel
        else
            sudo yum install -y sqlite sqlite-devel
        fi
        ;;
    arch|manjaro)
        echo "Installing SQLite on Arch Linux..."
        sudo pacman -S --noconfirm sqlite
        ;;
    *)
        echo "ERROR: Unsupported OS: $OS"
        echo "Please install SQLite manually for your OS."
        exit 1
        ;;
esac

# Verify installation
echo ""
echo "Verifying SQLite installation..."
if command -v sqlite3 &> /dev/null; then
    SQLITE_VERSION=$(sqlite3 --version | awk '{print $1}')
    echo "✓ SQLite command-line tool installed: version $SQLITE_VERSION"
else
    echo "ERROR: SQLite installation failed"
    exit 1
fi

# Verify Python sqlite3 module
echo "Verifying Python sqlite3 module..."
if python3 -c "import sqlite3; print('SQLite version:', sqlite3.sqlite_version)" 2>/dev/null; then
    PYTHON_SQLITE_VERSION=$(python3 -c "import sqlite3; print(sqlite3.sqlite_version)" 2>/dev/null)
    echo "✓ Python sqlite3 module is available: version $PYTHON_SQLITE_VERSION"
else
    echo "WARNING: Python sqlite3 module check failed"
    echo "This is unusual - Python should have sqlite3 built-in"
    echo "You may need to reinstall Python or install python3-dev package"
fi

echo ""
echo "=========================================="
echo "SQLite installation completed successfully!"
echo "=========================================="
echo ""
echo "SQLite command-line tool: $(which sqlite3)"
echo "SQLite version: $(sqlite3 --version)"
echo ""
echo "You can now use SQLite in your Python application."
echo "The sqlite3 module is built into Python, so no additional"
echo "Python packages are required."

