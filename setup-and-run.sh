#!/bin/bash
# ============================================================================
# AWS IoT Pub/Sub GUI - Complete Setup and Run Script for Raspberry Pi
# ============================================================================
# This script automatically:
#   1. Checks and installs system dependencies (if needed)
#   2. Creates/uses a virtual environment
#   3. Installs all Python dependencies (PyQt6, awsiotsdk, etc.)
#   4. Runs the application
#
# Usage:
#   chmod +x setup-and-run.sh
#   ./setup-and-run.sh
#   OR
#   sh setup-and-run.sh  (will auto-detect and use bash)
#
# Or double-click the file in the file manager (after making it executable)
# ============================================================================

# Detect if running with sh and re-execute with bash if needed
if [ -z "$BASH_VERSION" ]; then
    # Not running with bash, try to re-execute with bash
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    else
        echo "Error: This script requires bash. Please install bash or run with: bash $0" >&2
        exit 1
    fi
fi

set -e  # Exit on error (we'll handle errors gracefully)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if running on Raspberry Pi (optional check)
# Note: This function is currently not used but available for future use
is_raspberry_pi() {
    if [ -f /proc/device-tree/model ]; then
        grep -qi "raspberry" /proc/device-tree/model 2>/dev/null
    else
        return 1
    fi
}

# Get the script directory (where this script is located)
# Use $0 which works in both bash and sh
# Note: We ensure bash is used above, but $0 is more portable
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$SCRIPT_DIR/venv"
APP_FILE="$SCRIPT_DIR/iot_pubsub_gui.py"

# Change to script directory
cd "$SCRIPT_DIR"

# Print header
clear
print_step "AWS IoT Pub/Sub GUI - Setup and Run"
echo ""
print_info "Script directory: $SCRIPT_DIR"
print_info "Virtual environment: $VENV_DIR"
echo ""

# ============================================================================
# Step 1: Check Python 3 installation
# ============================================================================
print_step "Step 1: Checking Python 3 Installation"

if ! command_exists python3; then
    print_error "Python 3 is not installed!"
    echo ""
    echo "Please install Python 3 first:"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install -y python3 python3-pip python3-venv"
    echo ""
    read -p "Press Enter to exit..."
    exit 1
fi

PYTHON_VERSION=$(python3 --version)
print_success "Python 3 found: $PYTHON_VERSION"

# Check if python3-venv is available
if ! python3 -m venv --help >/dev/null 2>&1; then
    print_warning "python3-venv module not found"
    echo ""
    echo "Installing python3-venv..."
    if command_exists sudo; then
        sudo apt-get update -qq
        sudo apt-get install -y python3-venv
        print_success "python3-venv installed"
    else
        print_error "Cannot install python3-venv without sudo"
        echo "Please run: sudo apt-get install -y python3-venv"
        read -p "Press Enter to exit..."
        exit 1
    fi
fi

# ============================================================================
# Step 2: Check and install system dependencies (if needed)
# ============================================================================
print_step "Step 2: Checking System Dependencies"

# Essential system packages for PyQt6 on Raspberry Pi
SYSTEM_PACKAGES=(
    "python3-dev"
    "build-essential"
    "libxcb-xinerama0"
    "libxkbcommon-x11-0"
    "libqt6gui6"
    "libqt6widgets6"
    "libqt6core6"
)

MISSING_PACKAGES=()

for package in "${SYSTEM_PACKAGES[@]}"; do
    if ! dpkg -l | grep -q "^ii  $package "; then
        MISSING_PACKAGES+=("$package")
    fi
done

if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    print_warning "Some system packages may be missing for PyQt6"
    echo "Missing packages: ${MISSING_PACKAGES[*]}"
    echo ""
    
    if command_exists sudo; then
        echo "Would you like to install missing system packages? (requires sudo)"
        read -p "Install system packages? (y/n) " -n 1 -r
        echo ""
        
        # Check if reply is 'y' or 'Y' (POSIX-compatible)
        case "$REPLY" in
            [Yy]*)
                print_info "Updating package list..."
                sudo apt-get update -qq
                
                print_info "Installing system packages..."
                sudo apt-get install -y "${MISSING_PACKAGES[@]}" || {
                    print_error "Failed to install some system packages"
                    print_warning "Continuing anyway - PyQt6 installation may fail"
                }
                print_success "System packages installed"
                ;;
            *)
                print_warning "Skipping system package installation"
                print_warning "PyQt6 installation may fail if dependencies are missing"
                ;;
        esac
    else
        print_warning "sudo not available - skipping system package installation"
        print_warning "If PyQt6 installation fails, run:"
        echo "  sudo apt-get install -y ${MISSING_PACKAGES[*]}"
    fi
else
    print_success "All essential system packages are installed"
fi

# ============================================================================
# Step 3: Create or use existing virtual environment
# ============================================================================
print_step "Step 3: Setting Up Virtual Environment"

if [ -d "$VENV_DIR" ]; then
    print_info "Virtual environment already exists at: $VENV_DIR"
    print_info "Using existing virtual environment"
else
    print_info "Creating new virtual environment..."
    python3 -m venv "$VENV_DIR" || {
        print_error "Failed to create virtual environment"
        echo ""
        echo "Make sure python3-venv is installed:"
        echo "  sudo apt-get install -y python3-venv"
        read -p "Press Enter to exit..."
        exit 1
    }
    print_success "Virtual environment created at: $VENV_DIR"
fi

# Activate virtual environment
print_info "Activating virtual environment..."
source "$VENV_DIR/bin/activate" || {
    print_error "Failed to activate virtual environment"
    read -p "Press Enter to exit..."
    exit 1
}

# Verify we're using venv Python
VENV_PYTHON=$(which python)
# Check if Python path starts with VENV_DIR (POSIX-compatible)
case "$VENV_PYTHON" in
    "$VENV_DIR"*)
        # Python is from venv, good
        ;;
    *)
        print_error "Virtual environment activation failed"
        print_error "Expected Python from: $VENV_DIR"
        print_error "Got Python from: $VENV_PYTHON"
        read -p "Press Enter to exit..."
        exit 1
        ;;
esac

print_success "Virtual environment activated"
print_info "Using Python: $VENV_PYTHON"

# ============================================================================
# Step 4: Upgrade pip, setuptools, wheel
# ============================================================================
print_step "Step 4: Upgrading pip and Build Tools"

print_info "Upgrading pip, setuptools, and wheel..."
python -m pip install --upgrade --quiet pip setuptools wheel || {
    print_error "Failed to upgrade pip"
    print_warning "Continuing anyway..."
}

PIP_VERSION=$(python -m pip --version | cut -d' ' -f2)
print_success "pip upgraded to version: $PIP_VERSION"

# ============================================================================
# Step 5: Install Python dependencies
# ============================================================================
print_step "Step 5: Installing Python Dependencies"

# Check if packages are already installed
PYQT6_INSTALLED=false
AWSIOT_INSTALLED=false

if python -c "import PyQt6" 2>/dev/null; then
    PYQT6_VERSION=$(python -c "import PyQt6; print(PyQt6.__version__)" 2>/dev/null || echo "unknown")
    print_info "PyQt6 already installed: $PYQT6_VERSION"
    PYQT6_INSTALLED=true
fi

if python -c "import awsiot" 2>/dev/null; then
    print_info "AWS IoT SDK already installed"
    AWSIOT_INSTALLED=true
fi

# Install PyQt6 if needed
if [ "$PYQT6_INSTALLED" = false ]; then
    print_info "Installing PyQt6..."
    print_warning "This may take 30-60 minutes on Raspberry Pi if building from source"
    print_info "If pre-built wheels are available, installation will be faster"
    echo ""
    
    # Set environment variables for PyQt6 (if needed)
    export QT_SELECT=qt6 2>/dev/null || true
    
    python -m pip install PyQt6 || {
        print_error "Failed to install PyQt6"
        echo ""
        echo "Common solutions:"
        echo "1. Install system dependencies:"
        echo "   sudo apt-get install -y libxcb-xinerama0 libxkbcommon-x11-0 libqt6gui6 libqt6widgets6"
        echo ""
        echo "2. Try installing with system packages:"
        echo "   sudo apt-get install -y python3-pyqt6"
        echo ""
        echo "3. Check internet connection and try again"
        echo ""
        read -p "Press Enter to exit..."
        exit 1
    }
    
    # Verify installation
    if python -c "import PyQt6" 2>/dev/null; then
        PYQT6_VERSION=$(python -c "import PyQt6; print(PyQt6.__version__)" 2>/dev/null || echo "unknown")
        print_success "PyQt6 installed successfully: $PYQT6_VERSION"
    else
        print_error "PyQt6 installation verification failed"
        read -p "Press Enter to exit..."
        exit 1
    fi
else
    print_success "PyQt6 is already installed"
fi

# Install AWS IoT SDK if needed
if [ "$AWSIOT_INSTALLED" = false ]; then
    print_info "Installing AWS IoT SDK (awsiotsdk)..."
    python -m pip install awsiotsdk || {
        print_error "Failed to install AWS IoT SDK"
        echo ""
        echo "Common solutions:"
        echo "1. Check internet connection"
        echo "2. Try: python -m pip install --upgrade awsiotsdk"
        echo ""
        read -p "Press Enter to exit..."
        exit 1
    }
    
    # Verify installation
    if python -c "import awsiot" 2>/dev/null; then
        print_success "AWS IoT SDK installed successfully"
    else
        print_error "AWS IoT SDK installation verification failed"
        read -p "Press Enter to exit..."
        exit 1
    fi
else
    print_success "AWS IoT SDK is already installed"
fi

# Install additional dependencies (usually installed with awsiotsdk, but ensure they're there)
print_info "Ensuring additional dependencies are installed..."
python -m pip install --quiet awscrt cryptography python-dateutil || {
    print_warning "Some additional dependencies may have failed to install"
    print_warning "Continuing anyway..."
}

print_success "All Python dependencies are installed"

# ============================================================================
# Step 6: Verify application file exists
# ============================================================================
print_step "Step 6: Verifying Application Files"

if [ ! -f "$APP_FILE" ]; then
    print_error "Application file not found: $APP_FILE"
    read -p "Press Enter to exit..."
    exit 1
fi

print_success "Application file found: $APP_FILE"

# Check for certificate files (warn if missing, but don't fail)
CERT_FILES=(
    "AmazonRootCA1.pem"
    "ebb0b9fb27d1eb1ca52f7f89260e123a992759bf3b630f9863575015132ebbef-certificate.pem.crt"
    "ebb0b9fb27d1eb1ca52f7f89260e123a992759bf3b630f9863575015132ebbef-private.pem.key"
)

MISSING_CERTS=()
for cert in "${CERT_FILES[@]}"; do
    if [ ! -f "$SCRIPT_DIR/$cert" ]; then
        MISSING_CERTS+=("$cert")
    fi
done

if [ ${#MISSING_CERTS[@]} -gt 0 ]; then
    print_warning "Some certificate files are missing:"
    for cert in "${MISSING_CERTS[@]}"; do
        echo "  - $cert"
    done
    echo ""
    print_warning "The application may not be able to connect to AWS IoT without these files"
else
    print_success "All certificate files found"
fi

# ============================================================================
# Step 7: Pull latest code from git (if in a git repository)
# ============================================================================
print_step "Step 7: Pulling Latest Code from Git"

if [ -d ".git" ]; then
    GIT_BRANCH="${GIT_BRANCH:-main}"
    
    # Check git remote configuration
    GIT_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
    if [ -n "$GIT_REMOTE" ]; then
        print_info "Git remote: $GIT_REMOTE"
        
        # Ensure we're on the correct branch
        CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
        if [ -n "$CURRENT_BRANCH" ] && [ "$CURRENT_BRANCH" != "$GIT_BRANCH" ]; then
            print_info "Switching to $GIT_BRANCH branch..."
            if git checkout "$GIT_BRANCH" 2>/dev/null; then
                print_success "Switched to $GIT_BRANCH branch"
            else
                print_warning "Could not switch to $GIT_BRANCH, continuing with current branch..."
            fi
        else
            print_info "Already on $GIT_BRANCH branch"
        fi
        
        # Pull latest code
        print_info "Pulling latest code from origin/$GIT_BRANCH..."
        if git pull origin "$GIT_BRANCH" 2>/dev/null; then
            print_success "Successfully pulled latest code from git"
        else
            print_warning "Failed to pull latest code from git, continuing with current code..."
        fi
    else
        print_warning "No git remote found, skipping git pull"
    fi
else
    print_info "Not a git repository, skipping git pull"
fi

# ============================================================================
# Step 8: Run the application
# ============================================================================
print_step "Step 8: Starting Application"
echo ""

# Check if DISPLAY is set (for GUI)
if [ -z "$DISPLAY" ] && [ -z "$SSH_CLIENT" ] && [ -z "$SSH_TTY" ]; then
    # Not in SSH, but DISPLAY not set - try to set it
    if [ -n "$XDG_SESSION_ID" ] || [ -n "$WAYLAND_DISPLAY" ]; then
        # Likely in a desktop session
        export DISPLAY=:0 2>/dev/null || true
    fi
fi

if [ -z "$DISPLAY" ]; then
    print_warning "DISPLAY environment variable is not set"
    print_warning "If running via SSH, use: ssh -X pi@raspberrypi-ip"
    print_warning "Or set DISPLAY manually: export DISPLAY=:0"
    echo ""
fi

print_info "Launching AWS IoT Pub/Sub GUI..."
echo ""
echo "----------------------------------------"
echo ""

# Run the application
python "$APP_FILE"

# Capture exit code
EXIT_CODE=$?

echo ""
echo "----------------------------------------"
echo ""

if [ $EXIT_CODE -eq 0 ]; then
    print_success "Application exited normally"
else
    print_error "Application exited with error code: $EXIT_CODE"
    echo ""
    echo "Common issues:"
    echo "1. Certificate files missing or incorrect"
    echo "2. Network connectivity issues"
    echo "3. AWS IoT endpoint configuration"
    echo "4. Display/GUI issues (if running via SSH, use: ssh -X)"
    echo ""
fi

# Deactivate virtual environment (optional, script is ending anyway)
deactivate 2>/dev/null || true

# Keep terminal open if there was an error (for double-click execution)
if [ $EXIT_CODE -ne 0 ]; then
    echo ""
    read -p "Press Enter to exit..."
fi

exit $EXIT_CODE

