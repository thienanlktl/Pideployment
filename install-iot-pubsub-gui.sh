#!/bin/bash
# ============================================================================
# IoT PubSub GUI - One-Click Installer Script
# ============================================================================
# This script installs the IoT PubSub GUI application on Raspberry Pi
# Usage: bash install-iot-pubsub-gui.sh
#
# IMPORTANT: This script must be run with bash, not sh
# ============================================================================

# Ensure script is run with bash
if [ -z "$BASH_VERSION" ]; then
    echo "Error: This script must be run with bash, not sh"
    echo "Please run: bash install-iot-pubsub-gui.sh"
    exit 1
fi
#
# What it does:
# - Updates system packages
# - Installs required system dependencies
# - Clones the repository
# - Creates virtual environment
# - Installs Python dependencies
# - Creates desktop launcher
# ============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO_URL="https://github.com/thienanlktl/Pideployment.git"
INSTALL_DIR="$HOME/iot-pubsub-gui"
BRANCH="main"

# Print functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_step() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${GREEN}========================================${NC}"
}

# Check if running on Linux (more flexible check for Raspberry Pi OS)
if [[ "$OSTYPE" != "linux-gnu"* ]] && [[ "$OSTYPE" != "linux"* ]] && [[ "$(uname -s)" != "Linux" ]]; then
    print_error "This script is designed for Linux/Raspberry Pi OS"
    print_error "Detected OS: $OSTYPE"
    exit 1
fi

# Check if bash is available
if ! command -v bash &> /dev/null; then
    print_error "bash is required but not found. Please install bash first."
    exit 1
fi

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_error "Please do not run this script as root. It will ask for sudo when needed."
    exit 1
fi

print_step "IoT PubSub GUI - Installation Script"
print_info "This script will install the IoT PubSub GUI application"
print_info "Installation directory: $INSTALL_DIR"
echo ""

# ============================================================================
# Step 1: Update system packages
# ============================================================================
print_step "Step 1: Updating System Packages"

print_info "Updating package list (this may take a few minutes)..."

if sudo apt-get update; then
    print_success "Package list updated"
else
    print_error "Failed to update package list"
    exit 1
fi

print_info "Upgrading system packages (this may take several minutes)..."

if sudo apt-get upgrade -y; then
    print_success "System packages upgraded"
else
    print_warning "Some packages may have failed to upgrade. Continuing..."
fi

# ============================================================================
# Step 2: Install system dependencies
# ============================================================================
print_step "Step 2: Installing System Dependencies"

print_info "Installing required system packages..."

# Required packages (must be installed)
REQUIRED_PACKAGES=(
    "git"
    "python3"
    "python3-pip"
    "python3-venv"
    "python3-dev"
    "build-essential"
    "sqlite3"
    "libsqlite3-dev"
)

# Optional packages (for GUI support, may not be available on all systems)
OPTIONAL_PACKAGES=(
    "libxcb-xinerama0"
    "libxkbcommon-x11-0"
    "libqt6gui6"
    "libqt6widgets6"
    "libqt6core6"
    "libglib2.0-0"
)

# OpenGL packages - try different names for different systems
OPENGL_PACKAGES=(
    "libgl1-mesa-glx"           # Standard Debian/Ubuntu
    "libgl1"                     # Alternative name
    "mesa-common-dev"            # Development package
)

# Check and install required packages
MISSING_REQUIRED=()
for package in "${REQUIRED_PACKAGES[@]}"; do
    if ! dpkg -l 2>/dev/null | grep -q "^ii[[:space:]]*$package[[:space:]]" && \
       ! dpkg -l 2>/dev/null | grep -q "^ii[[:space:]]*$package:"; then
        MISSING_REQUIRED+=("$package")
    fi
done

if [ ${#MISSING_REQUIRED[@]} -gt 0 ]; then
    print_info "Installing required packages: ${MISSING_REQUIRED[*]}"
    if sudo apt-get install -y "${MISSING_REQUIRED[@]}"; then
        print_success "Required packages installed"
    else
        print_error "Failed to install required packages"
        exit 1
    fi
else
    print_success "All required packages are already installed"
fi

# Check and install optional packages
MISSING_OPTIONAL=()
for package in "${OPTIONAL_PACKAGES[@]}"; do
    if ! dpkg -l 2>/dev/null | grep -q "^ii[[:space:]]*$package[[:space:]]" && \
       ! dpkg -l 2>/dev/null | grep -q "^ii[[:space:]]*$package:"; then
        MISSING_OPTIONAL+=("$package")
    fi
done

if [ ${#MISSING_OPTIONAL[@]} -gt 0 ]; then
    print_info "Installing optional packages: ${MISSING_OPTIONAL[*]}"
    if sudo apt-get install -y "${MISSING_OPTIONAL[@]}" 2>/dev/null; then
        print_success "Optional packages installed"
    else
        print_warning "Some optional packages could not be installed (this may be okay)"
    fi
fi

# Try to install OpenGL support (try each package name until one works)
OPENGL_INSTALLED=false
for gl_package in "${OPENGL_PACKAGES[@]}"; do
    if dpkg -l 2>/dev/null | grep -q "^ii[[:space:]]*$gl_package[[:space:]]" || \
       dpkg -l 2>/dev/null | grep -q "^ii[[:space:]]*$gl_package:"; then
        OPENGL_INSTALLED=true
        print_success "OpenGL support already installed ($gl_package)"
        break
    fi
done

if [ "$OPENGL_INSTALLED" = false ]; then
    print_info "Attempting to install OpenGL support..."
    for gl_package in "${OPENGL_PACKAGES[@]}"; do
        if sudo apt-get install -y "$gl_package" 2>/dev/null; then
            print_success "OpenGL support installed ($gl_package)"
            OPENGL_INSTALLED=true
            break
        fi
    done
    
    if [ "$OPENGL_INSTALLED" = false ]; then
        print_warning "Could not install OpenGL packages - GUI may still work on Raspberry Pi"
        print_info "Raspberry Pi uses its own OpenGL implementation which may already be available"
    fi
fi

# ============================================================================
# Step 3: Clone or update repository
# ============================================================================
print_step "Step 3: Setting Up Repository"

if [ -d "$INSTALL_DIR" ]; then
    print_info "Installation directory exists. Updating repository..."
    cd "$INSTALL_DIR"
    if [ -d ".git" ]; then
        print_info "Pulling latest changes from $BRANCH branch..."
        if git fetch origin 2>/dev/null && git reset --hard "origin/$BRANCH" 2>/dev/null; then
            print_success "Repository updated"
        else
            print_warning "Could not update repository (git may not be available or no network access)"
            print_warning "Using existing files in directory"
        fi
    else
        print_warning "Directory exists but is not a git repository."
        print_warning "If you need to update, use the standalone installer or clone manually."
    fi
else
    print_info "Cloning repository from $REPO_URL..."
    if git clone -b "$BRANCH" "$REPO_URL" "$INSTALL_DIR" 2>/dev/null; then
        print_success "Repository cloned"
    else
        print_error "Failed to clone repository"
        print_error "Possible reasons:"
        print_error "  - No internet connection"
        print_error "  - Git not installed"
        print_error "  - Repository access denied (private repo requires authentication)"
        echo ""
        print_warning "SOLUTION: Use the standalone installer instead:"
        print_warning "  install-iot-pubsub-gui-standalone.sh"
        print_warning "  This installer packages all files and doesn't require git!"
        exit 1
    fi
fi

cd "$INSTALL_DIR"

# ============================================================================
# Step 4: Create virtual environment
# ============================================================================
print_step "Step 4: Creating Virtual Environment"

VENV_DIR="$INSTALL_DIR/venv"

if [ -d "$VENV_DIR" ]; then
    print_info "Virtual environment already exists"
else
    print_info "Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
    print_success "Virtual environment created"
fi

# Activate virtual environment
print_info "Activating virtual environment..."
# Use absolute path to ensure it works
if [ -f "$VENV_DIR/bin/activate" ]; then
    source "$VENV_DIR/bin/activate"
else
    print_error "Virtual environment activation script not found"
    exit 1
fi

# Upgrade pip
print_info "Upgrading pip..."
pip install --upgrade pip --quiet

# ============================================================================
# Step 5: Install Python dependencies
# ============================================================================
print_step "Step 5: Installing Python Dependencies"

if [ ! -f "requirements.txt" ]; then
    print_error "requirements.txt not found in repository"
    exit 1
fi

print_info "Installing Python packages from requirements.txt (this may take 10-30 minutes on first run)..."

if pip install -r requirements.txt; then
    print_success "Python dependencies installed"
else
    print_error "Failed to install Python dependencies"
    exit 1
fi

# Verify critical packages
print_info "Verifying critical packages..."
python3 -c "import PyQt6; import awsiot; import sqlite3" && {
    print_success "Critical packages verified"
} || {
    print_error "Critical packages verification failed"
    exit 1
}

# Verify SQLite3 database support
print_info "Verifying SQLite3 database support..."
python3 -c "import sqlite3; conn = sqlite3.connect(':memory:'); conn.execute('CREATE TABLE test (id INTEGER)'); conn.close()" && {
    print_success "SQLite3 database support verified"
} || {
    print_error "SQLite3 database support verification failed"
    print_warning "The application requires SQLite3 for message storage"
    exit 1
}

# ============================================================================
# Step 6: Create desktop launcher
# ============================================================================
print_step "Step 6: Creating Desktop Launcher"

DESKTOP_DIR="$HOME/Desktop"
DESKTOP_FILE="$DESKTOP_DIR/iot-pubsub-gui.desktop"

# Ensure Desktop directory exists
mkdir -p "$DESKTOP_DIR"

# Create desktop launcher
print_info "Creating desktop launcher..."

cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=IoT PubSub GUI
Comment=Launch IoT PubSub GUI Application
Exec=bash -c "cd '$INSTALL_DIR' && source venv/bin/activate && python3 iot_pubsub_gui.py"
Path=$INSTALL_DIR
Icon=application-x-executable
Terminal=false
Categories=Network;Utility;
StartupNotify=true
Keywords=IoT;AWS;MQTT;PubSub;
EOF

# Make launcher executable
chmod +x "$DESKTOP_FILE"

# Make desktop file trusted (required for some desktop environments)
# Try multiple methods for different desktop environments
if command -v gio &> /dev/null; then
    gio set "$DESKTOP_FILE" metadata::trusted true 2>/dev/null || true
fi

# Alternative method for making desktop file executable and trusted
chmod +x "$DESKTOP_FILE" 2>/dev/null || true

# Refresh desktop (if possible)
if command -v update-desktop-database &> /dev/null; then
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
fi

# For Raspberry Pi OS with LXDE/PiX desktop
if [ -d "$HOME/.local/share/applications" ]; then
    cp "$DESKTOP_FILE" "$HOME/.local/share/applications/" 2>/dev/null || true
fi

print_success "Desktop launcher created: $DESKTOP_FILE"

# ============================================================================
# Step 7: Verify installation
# ============================================================================
print_step "Step 7: Verifying Installation"

# Check main application file
if [ ! -f "$INSTALL_DIR/iot_pubsub_gui.py" ]; then
    print_error "Main application file not found"
    exit 1
fi
print_success "Main application file found"

# Verify SQLite3 is available in Python
print_info "Verifying SQLite3 in Python environment..."
if python3 -c "import sqlite3; print('SQLite3 version:', sqlite3.sqlite_version)" 2>/dev/null; then
    print_success "SQLite3 is available in Python"
else
    print_warning "SQLite3 may not be properly configured in Python"
fi

# Check certificate files (warn if missing, but don't fail)
CERT_FILES=(
    "AmazonRootCA1.pem"
    "ebb0b9fb27d1eb1ca52f7f89260e123a992759bf3b630f9863575015132ebbef-certificate.pem.crt"
    "ebb0b9fb27d1eb1ca52f7f89260e123a992759bf3b630f9863575015132ebbef-private.pem.key"
)

MISSING_CERTS=()
for cert in "${CERT_FILES[@]}"; do
    if [ ! -f "$INSTALL_DIR/$cert" ]; then
        MISSING_CERTS+=("$cert")
    fi
done

if [ ${#MISSING_CERTS[@]} -gt 0 ]; then
    print_warning "Some certificate files are missing (application may not connect to AWS IoT):"
    for cert in "${MISSING_CERTS[@]}"; do
        echo "  - $cert"
    done
    print_info "You can add certificate files to: $INSTALL_DIR"
else
    print_success "All certificate files found"
fi

# ============================================================================
# Installation Complete
# ============================================================================
print_step "Installation Complete!"

print_success "IoT PubSub GUI has been successfully installed!"
echo ""
print_info "Installation directory: $INSTALL_DIR"
print_info "Desktop launcher: $DESKTOP_FILE"
echo ""
print_info "To run the application:"
echo "  1. Double-click the 'IoT PubSub GUI' icon on your desktop"
echo ""
echo "  2. Or run from terminal:"
echo "     cd $INSTALL_DIR"
echo "     source venv/bin/activate"
echo "     python3 iot_pubsub_gui.py"
echo ""
print_info "Note: Certificate files are required for AWS IoT connection."
print_info "Note: SQLite3 database will be created automatically when the application runs."
echo ""

