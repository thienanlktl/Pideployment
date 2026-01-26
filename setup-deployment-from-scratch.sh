#!/bin/bash
# ============================================================================
# Complete Deployment Setup from Scratch
# ============================================================================
# This script sets up the entire deployment system on Raspberry Pi from scratch
# It handles:
#   1. System dependencies installation
#   2. Git repository cloning (if needed)
#   3. SSH key generation and GitHub setup
#   4. Git repository configuration
#   5. Python dependencies (Flask for webhook)
#   6. Webhook listener setup
#   7. Systemd service installation
#   8. Testing and verification
#   9. ngrok setup with pre-configured token
#   10. GitHub webhook creation (uses .github_token if available)
#
# Usage:
#   Option 1: Run from any directory (will clone repo)
#     chmod +x setup-deployment-from-scratch.sh
#     ./setup-deployment-from-scratch.sh
#
#   Option 2: Run from cloned repository directory
#     cd ~/Pideployment
#     ./setup-deployment-from-scratch.sh
#
#   Option 3: With GitHub token (for auto webhook creation)
#     export GITHUB_TOKEN="your_token"
#     ./setup-deployment-from-scratch.sh
#     OR place token in .github_token file in project directory
# ============================================================================

# Detect if running with sh and re-execute with bash if needed
if [ -z "$BASH_VERSION" ]; then
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    else
        echo "Error: This script requires bash." >&2
        exit 1
    fi
fi

# Don't exit on error immediately - we'll handle errors gracefully
set +e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_step() {
    echo ""
    echo -e "${CYAN}============================================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}============================================================================${NC}"
    echo ""
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if we're in a git repository
is_git_repo() {
    git rev-parse --git-dir >/dev/null 2>&1
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Configuration (user can modify these via environment variables)
GITHUB_USER="${GITHUB_USER:-thienanlktl}"
REPO_NAME="${REPO_NAME:-Pideployment}"
GIT_BRANCH="${GIT_BRANCH:-main}"
WEBHOOK_PORT="${WEBHOOK_PORT:-9000}"

# Determine project directory
# If we're in a git repo, use current directory, otherwise we'll clone
if is_git_repo; then
    PROJECT_DIR="$SCRIPT_DIR"
    REPO_CLONED=true
else
    # Default to ~/Pideployment or current directory name
    PROJECT_DIR="${PROJECT_DIR:-$HOME/$REPO_NAME}"
    REPO_CLONED=false
fi

# Print header
clear
print_step "Complete Deployment Setup from Scratch"
echo ""
print_info "This script will set up the entire deployment system on your Raspberry Pi"
echo ""
print_info "Configuration:"
echo "  - GitHub User: $GITHUB_USER"
echo "  - Repository: $REPO_NAME"
echo "  - Branch: $GIT_BRANCH"
echo "  - Project Directory: $PROJECT_DIR"
echo "  - Webhook Port: $WEBHOOK_PORT"
echo ""

# Check if SSH key exists in current directory (before cloning)
EXISTING_KEY="$SCRIPT_DIR/id_ed25519"
if [ -f "$EXISTING_KEY" ]; then
    print_info "Found existing SSH key in current directory: $EXISTING_KEY"
    print_info "Will automatically set it up and use it for SSH clone"
fi

# Check if we need to clone the repository
if [ "$REPO_CLONED" = false ]; then
    print_info "Not in a git repository - will clone automatically"
    echo "The script will automatically clone the repository to: $PROJECT_DIR"
    CLONE_REPO=true
else
    CLONE_REPO=false
    print_info "Already in git repository: $PROJECT_DIR"
fi

echo ""
print_info "Starting automated setup (all steps will run automatically)..."
sleep 2
echo ""

# ============================================================================
# Step 0: Check for existing SSH key and set up for cloning
# ============================================================================
print_step "Step 0: Checking for Existing SSH Key"

SSH_DIR="$HOME/.ssh"
EXISTING_KEY="$SCRIPT_DIR/id_ed25519"
EXISTING_KEY_PUB="$SCRIPT_DIR/id_ed25519.pub"
KEY_NAME="id_ed25519_iot_gui"
KEY_PATH="$SSH_DIR/$KEY_NAME"
USE_EXISTING_KEY=false

# Check if SSH key exists in current directory
if [ -f "$EXISTING_KEY" ]; then
    print_success "Found existing SSH private key: $EXISTING_KEY"
    
    # Check if public key also exists
    if [ -f "$EXISTING_KEY_PUB" ]; then
        print_success "Found existing SSH public key: $EXISTING_KEY_PUB"
        USE_EXISTING_KEY=true
    else
        print_warning "Public key not found, but private key exists"
        print_info "Will use existing private key and generate public key if needed"
        USE_EXISTING_KEY=true
    fi
    
    # Create .ssh directory if needed
    if [ ! -d "$SSH_DIR" ]; then
        print_info "Creating .ssh directory..."
        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"
    fi
    
    # Copy key to .ssh directory
    print_info "Setting up SSH key for git operations..."
    cp "$EXISTING_KEY" "$KEY_PATH"
    chmod 600 "$KEY_PATH"
    
    if [ -f "$EXISTING_KEY_PUB" ]; then
        cp "$EXISTING_KEY_PUB" "$KEY_PATH.pub"
        chmod 644 "$KEY_PATH.pub"
    else
        # Try to generate public key from private key
        print_info "Generating public key from private key..."
        if ssh-keygen -y -f "$KEY_PATH" > "$KEY_PATH.pub" 2>/dev/null; then
            chmod 644 "$KEY_PATH.pub"
            print_success "Public key generated"
        else
            print_warning "Could not generate public key, but will try to use private key"
        fi
    fi
    
    # Configure SSH config
    SSH_CONFIG="$SSH_DIR/config"
    CONFIG_ENTRY="Host github.com-iot-gui
    HostName github.com
    User git
    IdentityFile $KEY_PATH
    IdentitiesOnly yes
"
    
    if [ ! -f "$SSH_CONFIG" ] || ! grep -q "Host github.com-iot-gui" "$SSH_CONFIG" 2>/dev/null; then
        print_info "Configuring SSH for GitHub..."
        if [ ! -f "$SSH_CONFIG" ]; then
            touch "$SSH_CONFIG"
            chmod 600 "$SSH_CONFIG"
        fi
        echo "" >> "$SSH_CONFIG"
        echo "# GitHub Deploy Key for IoT Pub/Sub GUI" >> "$SSH_CONFIG"
        echo "$CONFIG_ENTRY" >> "$SSH_CONFIG"
        print_success "SSH config updated"
    fi
    
    # Test SSH connection
    print_info "Testing SSH connection to GitHub..."
    SSH_TEST_OUTPUT=$(ssh -i "$KEY_PATH" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -T git@github.com 2>&1)
    if echo "$SSH_TEST_OUTPUT" | grep -q "successfully authenticated"; then
        print_success "SSH connection to GitHub successful!"
        SSH_WORKING=true
    elif echo "$SSH_TEST_OUTPUT" | grep -qi "permission denied"; then
        print_warning "SSH key may not be added to GitHub yet"
        print_info "Will try SSH clone first, fallback to HTTPS if needed"
        SSH_WORKING=false
    else
        print_warning "SSH connection test inconclusive"
        print_info "Will try SSH clone first, fallback to HTTPS if needed"
        SSH_WORKING=false
    fi
else
    print_info "No existing SSH key found in current directory"
    print_info "Will use HTTPS for initial clone, then set up SSH key later"
    USE_EXISTING_KEY=false
    SSH_WORKING=false
fi

# ============================================================================
# Step 0.5: Clone repository if needed
# ============================================================================
if [ "$CLONE_REPO" = true ]; then
    print_step "Step 0.5: Cloning Repository"
    
    # Check if directory already exists
    if [ -d "$PROJECT_DIR" ]; then
        print_info "Directory already exists: $PROJECT_DIR"
        print_info "Using existing directory (not cloning)"
        CLONE_REPO=false
    fi
    
    if [ "$CLONE_REPO" = true ]; then
        print_info "Cloning repository from GitHub..."
        
        # Use SSH if we have a working key, otherwise HTTPS
        if [ "$USE_EXISTING_KEY" = true ]; then
            SSH_REPO_URL="git@github.com-iot-gui:$GITHUB_USER/$REPO_NAME.git"
            print_info "Using SSH with existing key..."
            
            # Try SSH clone with the key
            if GIT_SSH_COMMAND="ssh -i $KEY_PATH -o IdentitiesOnly=yes -o StrictHostKeyChecking=no" git clone "$SSH_REPO_URL" "$PROJECT_DIR" 2>/dev/null; then
                print_success "Repository cloned successfully via SSH"
                cd "$PROJECT_DIR" || exit 1
                SCRIPT_DIR="$PROJECT_DIR"
            elif [ "$SSH_WORKING" = true ]; then
                # If SSH test passed but clone failed, try standard SSH URL
                SSH_REPO_URL_STD="git@github.com:$GITHUB_USER/$REPO_NAME.git"
                print_info "Trying standard SSH URL..."
                if GIT_SSH_COMMAND="ssh -i $KEY_PATH -o IdentitiesOnly=yes -o StrictHostKeyChecking=no" git clone "$SSH_REPO_URL_STD" "$PROJECT_DIR" 2>/dev/null; then
                    print_success "Repository cloned successfully via SSH (standard URL)"
                    cd "$PROJECT_DIR" || exit 1
                    SCRIPT_DIR="$PROJECT_DIR"
                else
                    print_warning "SSH clone failed, trying HTTPS..."
                    HTTPS_REPO_URL="https://github.com/$GITHUB_USER/$REPO_NAME.git"
                    if git clone "$HTTPS_REPO_URL" "$PROJECT_DIR"; then
                        print_success "Repository cloned successfully via HTTPS"
                        cd "$PROJECT_DIR" || exit 1
                        SCRIPT_DIR="$PROJECT_DIR"
                    else
                        print_error "Failed to clone repository"
                        print_info "Make sure you have internet connection and the repository exists"
                        exit 1
                    fi
                fi
            else
                print_warning "SSH key may not be added to GitHub yet, trying HTTPS..."
                HTTPS_REPO_URL="https://github.com/$GITHUB_USER/$REPO_NAME.git"
                if git clone "$HTTPS_REPO_URL" "$PROJECT_DIR"; then
                    print_success "Repository cloned successfully via HTTPS"
                    print_info "After adding SSH key to GitHub, you can switch to SSH remote"
                    cd "$PROJECT_DIR" || exit 1
                    SCRIPT_DIR="$PROJECT_DIR"
                else
                    print_error "Failed to clone repository"
                    print_info "Make sure you have internet connection and the repository exists"
                    exit 1
                fi
            fi
        else
            HTTPS_REPO_URL="https://github.com/$GITHUB_USER/$REPO_NAME.git"
            print_info "Using HTTPS for initial clone..."
            if git clone "$HTTPS_REPO_URL" "$PROJECT_DIR"; then
                print_success "Repository cloned successfully"
                cd "$PROJECT_DIR" || exit 1
                SCRIPT_DIR="$PROJECT_DIR"
            else
                print_error "Failed to clone repository"
                print_info "Make sure you have internet connection and the repository exists"
                exit 1
            fi
        fi
    fi
fi

# Change to project directory
cd "$PROJECT_DIR" || {
    print_error "Cannot access project directory: $PROJECT_DIR"
    exit 1
}

# Verify we're in a git repository now
if ! is_git_repo; then
    print_error "Not in a git repository: $PROJECT_DIR"
    exit 1
fi

# ============================================================================
# Step 1: Check prerequisites
# ============================================================================
print_step "Step 1: Checking Prerequisites"

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    print_error "Please do not run this script as root (sudo)"
    print_info "The script will ask for sudo when needed"
    exit 1
fi

# Check Python 3
if ! command_exists python3; then
    print_warning "Python 3 is not installed"
    print_info "Installing Python 3..."
    sudo apt-get update -qq || {
        print_error "Failed to update package list"
        exit 1
    }
    sudo apt-get install -y python3 python3-pip python3-venv || {
        print_error "Failed to install Python 3"
        exit 1
    }
    print_success "Python 3 installed"
else
    PYTHON_VERSION=$(python3 --version 2>&1)
    print_success "Python 3 found: $PYTHON_VERSION"
fi

# Check git
if ! command_exists git; then
    print_warning "Git is not installed"
    print_info "Installing git..."
    sudo apt-get update -qq || {
        print_error "Failed to update package list"
        exit 1
    }
    sudo apt-get install -y git || {
        print_error "Failed to install git"
        exit 1
    }
    print_success "Git installed"
else
    GIT_VERSION=$(git --version)
    print_success "Git found: $GIT_VERSION"
fi

# Verify git repository
if ! is_git_repo; then
    print_error "Not in a git repository"
    exit 1
fi

# ============================================================================
# Step 2: Install system dependencies
# ============================================================================
print_step "Step 2: Installing System Dependencies"

print_info "Updating package list..."
if ! sudo apt-get update -qq; then
    print_error "Failed to update package list"
    exit 1
fi

print_info "Installing essential packages..."
sudo apt-get install -y \
    python3-dev \
    build-essential \
    libxcb-xinerama0 \
    libxkbcommon-x11-0 \
    libqt6gui6 \
    libqt6widgets6 \
    libqt6core6 \
    curl \
    2>&1 | grep -v "^\(Reading\|Building\|Get\)" || {
    print_warning "Some packages may have failed to install"
    print_warning "Continuing anyway..."
}

print_success "System dependencies installed"

# ============================================================================
# Step 3: Set up virtual environment
# ============================================================================
print_step "Step 3: Setting Up Virtual Environment"

VENV_DIR="$PROJECT_DIR/venv"

if [ -d "$VENV_DIR" ]; then
    print_info "Virtual environment already exists - using existing one"
    CREATE_VENV=false
else
    print_info "Virtual environment not found - creating new one"
    CREATE_VENV=true
fi

if [ "$CREATE_VENV" = true ]; then
    print_info "Creating virtual environment..."
    if ! python3 -m venv "$VENV_DIR" 2>/dev/null; then
        print_warning "Failed to create virtual environment, installing python3-venv..."
        sudo apt-get install -y python3-venv || {
            print_error "Failed to install python3-venv"
            exit 1
        }
        if ! python3 -m venv "$VENV_DIR"; then
            print_error "Failed to create virtual environment"
            exit 1
        fi
    fi
    print_success "Virtual environment created"
fi

# Activate virtual environment
print_info "Activating virtual environment..."
if [ ! -f "$VENV_DIR/bin/activate" ]; then
    print_error "Virtual environment activation script not found"
    exit 1
fi

source "$VENV_DIR/bin/activate" || {
    print_error "Failed to activate virtual environment"
    exit 1
}

# Verify activation
if [ "$VIRTUAL_ENV" != "$VENV_DIR" ]; then
    print_error "Virtual environment activation failed"
    exit 1
fi

# Upgrade pip
print_info "Upgrading pip..."
python -m pip install --upgrade --quiet pip setuptools wheel || {
    print_warning "Failed to upgrade pip, continuing anyway..."
}

print_success "Virtual environment ready"

# ============================================================================
# Step 4: Install Python dependencies
# ============================================================================
print_step "Step 4: Installing Python Dependencies"

# Install Flask for webhook listener (required)
print_info "Installing Flask (for webhook listener)..."
if ! python -m pip install --quiet "Flask>=2.0.0"; then
    print_error "Failed to install Flask - this is required"
    exit 1
fi
print_success "Flask installed"

# Install other dependencies from requirements.txt if it exists
if [ -f "$PROJECT_DIR/requirements.txt" ]; then
    print_info "Installing dependencies from requirements.txt..."
    python -m pip install --quiet -r "$PROJECT_DIR/requirements.txt" || {
        print_warning "Some dependencies from requirements.txt may have failed"
        print_info "Continuing anyway..."
    }
    print_success "Dependencies from requirements.txt installed"
else
    print_warning "No requirements.txt found"
    print_info "Installing core dependencies..."
    python -m pip install --quiet PyQt6 awsiotsdk awscrt cryptography python-dateutil || {
        print_warning "Some core dependencies may have failed"
        print_info "You may need to install them manually later"
    }
    print_success "Core dependencies installed"
fi

# ============================================================================
# Step 5: Verify required files exist
# ============================================================================
print_step "Step 5: Verifying Required Files"

REQUIRED_FILES=(
    "iot_pubsub_gui.py"
    "webhook_listener.py"
    "update-and-restart.sh"
)

MISSING_FILES=()
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$PROJECT_DIR/$file" ]; then
        MISSING_FILES+=("$file")
        print_warning "Required file not found: $file"
    else
        print_success "Found: $file"
    fi
done

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    print_warning "Some required files are missing: ${MISSING_FILES[*]}"
    print_info "Pulling latest code from repository..."
    
    # Try to pull latest code
    git pull origin "$GIT_BRANCH" 2>/dev/null || {
        print_warning "Could not pull latest code"
        print_info "Make sure the repository is up to date"
    }
    
    # Check again
    STILL_MISSING=()
    for file in "${MISSING_FILES[@]}"; do
        if [ ! -f "$PROJECT_DIR/$file" ]; then
            STILL_MISSING+=("$file")
        fi
    done
    
    if [ ${#STILL_MISSING[@]} -gt 0 ]; then
        print_error "Required files still missing: ${STILL_MISSING[*]}"
        print_info "Please ensure the repository contains all required files"
        print_info "You may need to check the repository manually"
    fi
fi

# ============================================================================
# Step 6: Verify/Setup SSH key for GitHub
# ============================================================================
print_step "Step 6: Verifying SSH Key Setup"

# If we already set up the key in Step 0, skip this
if [ "$USE_EXISTING_KEY" = true ] && [ -f "$KEY_PATH" ]; then
    print_info "SSH key already set up from existing key in directory"
    print_success "Using existing SSH key: $KEY_PATH"
    
    # Display public key for reference
    if [ -f "$KEY_PATH.pub" ]; then
        echo ""
        print_info "Your SSH public key (already configured on GitHub):"
        cat "$KEY_PATH.pub"
        echo ""
    fi
else
    # Generate new SSH key if needed
    SSH_DIR="$HOME/.ssh"
    KEY_NAME="id_ed25519_iot_gui"
    KEY_PATH="$SSH_DIR/$KEY_NAME"
    KEY_COMMENT="iot-gui-deploy@raspberrypi"
    
    # Create .ssh directory if needed
    if [ ! -d "$SSH_DIR" ]; then
        print_info "Creating .ssh directory..."
        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"
    fi
    
    # Check if key exists
    if [ -f "$KEY_PATH" ]; then
        print_info "SSH key already exists: $KEY_PATH"
        print_info "Using existing key"
    else
        print_info "Generating new SSH key pair..."
        if ! ssh-keygen -t ed25519 \
            -C "$KEY_COMMENT" \
            -f "$KEY_PATH" \
            -N "" \
            -q; then
            print_error "Failed to generate SSH key"
            exit 1
        fi
        
        chmod 600 "$KEY_PATH"
        chmod 644 "$KEY_PATH.pub"
        print_success "SSH key generated"
        
        # Configure SSH config
        SSH_CONFIG="$SSH_DIR/config"
        CONFIG_ENTRY="Host github.com-iot-gui
    HostName github.com
    User git
    IdentityFile $KEY_PATH
    IdentitiesOnly yes
"
        
        if [ ! -f "$SSH_CONFIG" ] || ! grep -q "Host github.com-iot-gui" "$SSH_CONFIG" 2>/dev/null; then
            print_info "Configuring SSH for GitHub..."
            if [ ! -f "$SSH_CONFIG" ]; then
                touch "$SSH_CONFIG"
                chmod 600 "$SSH_CONFIG"
            fi
            echo "" >> "$SSH_CONFIG"
            echo "# GitHub Deploy Key for IoT Pub/Sub GUI" >> "$SSH_CONFIG"
            echo "$CONFIG_ENTRY" >> "$SSH_CONFIG"
            print_success "SSH config updated"
        fi
        
        # Display public key
        echo ""
        print_step "SSH Public Key - Add to GitHub"
        echo ""
        print_warning "IMPORTANT: Copy the public key below and add it to GitHub"
        echo ""
        cat "$KEY_PATH.pub"
        echo ""
        echo ""
        print_info "GitHub Deploy Key URL:"
        echo "  https://github.com/$GITHUB_USER/$REPO_NAME/settings/keys"
        echo ""
        print_info "Note: If key is not added yet, the script will use HTTPS for cloning"
        print_info "You can add the key later and switch to SSH remote"
        sleep 3
        echo ""
    fi
fi

# ============================================================================
# Step 7: Configure Git repository
# ============================================================================
print_step "Step 7: Configuring Git Repository"

# Check current remote
CURRENT_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")

if [ -n "$CURRENT_REMOTE" ]; then
    print_info "Current git remote: $CURRENT_REMOTE"
    
    # Check if it's HTTPS and we have SSH key - auto-convert
    if echo "$CURRENT_REMOTE" | grep -q "^https://"; then
        if [ "$USE_EXISTING_KEY" = true ] && [ -f "$KEY_PATH" ]; then
            print_info "Repository is using HTTPS, auto-converting to SSH..."
            UPDATE_REMOTE=true
        else
            print_info "Repository is using HTTPS - keeping as is (no SSH key available)"
            UPDATE_REMOTE=false
        fi
    else
        print_info "Repository already using SSH - keeping as is"
        UPDATE_REMOTE=false
    fi
else
    UPDATE_REMOTE=true
    print_info "No git remote configured - will set it up"
fi

# Set git remote
if [ "$UPDATE_REMOTE" = true ]; then
    print_info "Setting git remote URL..."
    
    SSH_URL="git@github.com:$GITHUB_USER/$REPO_NAME.git"
    ALT_SSH_URL="git@github.com-iot-gui:$GITHUB_USER/$REPO_NAME.git"
    HTTPS_URL="https://github.com/$GITHUB_USER/$REPO_NAME.git"
    
    # Auto-select SSH if we have a working key, otherwise use HTTPS
    if [ "$USE_EXISTING_KEY" = true ] && [ -f "$KEY_PATH" ]; then
        print_info "Using SSH with existing key (automatic selection)"
        GIT_REMOTE_URL="$ALT_SSH_URL"
    else
        # Auto-select HTTPS if no SSH key, or try SSH first
        print_info "Auto-selecting git remote URL..."
        if [ -f "$KEY_PATH" ]; then
            print_info "SSH key found - trying SSH first"
            GIT_REMOTE_URL="$ALT_SSH_URL"
        else
            print_info "No SSH key - using HTTPS (can switch to SSH later)"
            GIT_REMOTE_URL="$HTTPS_URL"
        fi
    fi
    
    if git remote set-url origin "$GIT_REMOTE_URL" 2>/dev/null; then
        print_success "Git remote updated: $GIT_REMOTE_URL"
    elif git remote add origin "$GIT_REMOTE_URL" 2>/dev/null; then
        print_success "Git remote added: $GIT_REMOTE_URL"
    else
        print_error "Failed to set git remote"
        exit 1
    fi
fi

# Pull latest code
print_info "Pulling latest code from repository..."
if git pull origin "$GIT_BRANCH" 2>/dev/null; then
    print_success "Repository is up to date"
else
    print_warning "Could not pull latest code (this is OK if repository is already up to date)"
fi

# Test SSH connection (only if using SSH)
if echo "$(git remote get-url origin 2>/dev/null)" | grep -q "^git@"; then
    print_info "Testing SSH connection to GitHub..."
    if [ -f "$KEY_PATH" ]; then
        if ssh -i "$KEY_PATH" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
            print_success "SSH connection to GitHub successful!"
        else
            print_warning "SSH connection test completed"
            print_warning "If authentication failed, make sure you added the public key to GitHub"
        fi
    else
        if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
            print_success "SSH connection to GitHub successful!"
        else
            print_warning "SSH connection test completed"
        fi
    fi
fi

# ============================================================================
# Step 8: Generate webhook secret
# ============================================================================
print_step "Step 8: Generating Webhook Secret"

print_info "Generating secure webhook secret..."
WEBHOOK_SECRET=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))" 2>/dev/null || \
    openssl rand -base64 32 2>/dev/null | tr -d "=+/" | cut -c1-32 || \
    date +%s | sha256sum | base64 | head -c 32)

if [ -z "$WEBHOOK_SECRET" ]; then
    print_error "Failed to generate webhook secret"
    exit 1
fi

print_success "Webhook secret generated"
echo ""
print_warning "IMPORTANT: Save this secret - you'll need it for GitHub webhook setup"
echo ""
echo "Webhook Secret: $WEBHOOK_SECRET"
echo ""
print_info "Secret will be displayed again at the end of setup"

# Save secret to a file (with restricted permissions)
SECRET_FILE="$PROJECT_DIR/.webhook_secret"
echo "$WEBHOOK_SECRET" > "$SECRET_FILE"
chmod 600 "$SECRET_FILE"
print_info "Secret saved to: $SECRET_FILE (restricted permissions)"

# ============================================================================
# Step 9: Make scripts executable
# ============================================================================
print_step "Step 9: Setting Up Scripts"

SCRIPTS=(
    "update-and-restart.sh"
    "setup-ssh-key.sh"
    "setup-cron-fallback.sh"
    "test-deployment.sh"
    "setup-and-run.sh"
    "get-webhook-info.sh"
    "setup-ngrok.sh"
    "get-ngrok-url.sh"
    "create-github-webhook.sh"
)

for script in "${SCRIPTS[@]}"; do
    if [ -f "$PROJECT_DIR/$script" ]; then
        chmod +x "$PROJECT_DIR/$script"
        print_success "$script is now executable"
    else
        print_warning "$script not found (skipping)"
    fi
done

# ============================================================================
# Step 10: Configure systemd service
# ============================================================================
print_step "Step 10: Configuring Systemd Service"

SERVICE_FILE="$PROJECT_DIR/iot-gui-webhook.service"
SYSTEMD_SERVICE="/etc/systemd/system/iot-gui-webhook.service"

if [ ! -f "$SERVICE_FILE" ]; then
    print_warning "Service file not found: $SERVICE_FILE"
    print_info "Skipping systemd service setup"
    print_info "You can set it up manually later"
    SERVICE_INSTALLED=false
else
    print_info "Updating service file with correct paths..."
    
    # Get current user and home directory
    CURRENT_USER=$(whoami)
    
    # Create temporary service file with correct paths
    TEMP_SERVICE=$(mktemp)
    # Replace placeholders with actual values
    sed "s|/home/pi/Pideployment|$PROJECT_DIR|g" "$SERVICE_FILE" | \
    sed "s|User=pi|User=$CURRENT_USER|g" | \
    sed "s|Group=pi|Group=$CURRENT_USER|g" > "$TEMP_SERVICE"
    
    print_info "Installing systemd service..."
    if sudo cp "$TEMP_SERVICE" "$SYSTEMD_SERVICE"; then
        rm "$TEMP_SERVICE"
        
        print_info "Reloading systemd..."
        sudo systemctl daemon-reload || {
            print_warning "Failed to reload systemd"
        }
        
        print_info "Enabling service to start on boot..."
        sudo systemctl enable iot-gui-webhook.service || {
            print_warning "Failed to enable service"
        }
        
        # Automatically start the service
        print_info "Starting webhook service automatically..."
        if sudo systemctl start iot-gui-webhook.service; then
            sleep 2
            
            if sudo systemctl is-active --quiet iot-gui-webhook.service; then
                print_success "Webhook service is running"
                SERVICE_INSTALLED=true
            else
                print_warning "Webhook service may not have started correctly"
                print_info "Check status with: sudo systemctl status iot-gui-webhook.service"
                SERVICE_INSTALLED=true
            fi
        else
            print_warning "Failed to start service"
            print_info "Start it later with: sudo systemctl start iot-gui-webhook.service"
            SERVICE_INSTALLED=true
        fi
    else
        print_error "Failed to install systemd service"
        rm -f "$TEMP_SERVICE"
        SERVICE_INSTALLED=false
    fi
fi

# ============================================================================
# Step 11: Webhook Setup Information
# ============================================================================
print_step "Step 11: Webhook Setup Information"

print_info "We'll use ngrok to create a public URL for GitHub webhooks"
print_info "No router configuration needed - everything runs on Pi!"
echo ""

# ============================================================================
# Step 12: Setup ngrok for webhook access (no router config needed!)
# ============================================================================
print_step "Step 12: Setting Up ngrok Tunnel"

print_info "Using ngrok to create secure tunnel - no router configuration needed!"
print_info "ngrok creates a public URL that forwards to your Pi's webhook"
echo ""

NGROK_SETUP_SUCCESS=false
WEBHOOK_URL=""

# Check if ngrok setup script exists
if [ -f "$PROJECT_DIR/setup-ngrok.sh" ]; then
    print_info "Running ngrok setup..."
    chmod +x "$PROJECT_DIR/setup-ngrok.sh"
    
    # Check if authtoken is provided via environment variable or use default
    if [ -z "$NGROK_AUTHTOKEN" ]; then
        # Use the pre-configured token automatically
        NGROK_AUTHTOKEN="38HbghqIwfeBRpp4wdZHFkeTOT1_2Dh6671w4NZEUoFMpcVa6"
        print_info "Using pre-configured ngrok authtoken automatically"
    else
        print_info "Using ngrok authtoken from environment variable"
    fi
    
    # Run ngrok setup with token (non-interactive)
    print_info "Setting up ngrok automatically..."
    if NGROK_AUTHTOKEN="$NGROK_AUTHTOKEN" "$PROJECT_DIR/setup-ngrok.sh" "$NGROK_AUTHTOKEN" >/dev/null 2>&1; then
        NGROK_SETUP_SUCCESS=true
        print_success "ngrok setup completed"
    else
        # Try again with output visible for debugging
        print_info "Retrying ngrok setup..."
        if NGROK_AUTHTOKEN="$NGROK_AUTHTOKEN" "$PROJECT_DIR/setup-ngrok.sh" "$NGROK_AUTHTOKEN"; then
            NGROK_SETUP_SUCCESS=true
            print_success "ngrok setup completed"
        else
            print_warning "ngrok setup had issues - will retry getting URL"
            NGROK_SETUP_SUCCESS=false
        fi
    fi
    
    # Wait for ngrok to start and get URL
    print_info "Waiting for ngrok to start and get public URL..."
    
    # Start ngrok service if not running
    if ! sudo systemctl is-active --quiet iot-gui-ngrok.service 2>/dev/null; then
        print_info "Starting ngrok service..."
        sudo systemctl start iot-gui-ngrok.service 2>/dev/null || true
    fi
    
    # Try to get ngrok URL with retries
    MAX_RETRIES=15
    RETRY_COUNT=0
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        sleep 2
        NGROK_URL=$(curl -s --max-time 3 http://localhost:4040/api/tunnels 2>/dev/null | grep -oP '"public_url":"https://[^"]*' | head -1 | cut -d'"' -f4)
        if [ -n "$NGROK_URL" ]; then
            WEBHOOK_URL="$NGROK_URL/webhook"
            echo "$WEBHOOK_URL" > "$PROJECT_DIR/.ngrok_url"
            print_success "ngrok tunnel is active!"
            print_success "Public URL obtained: $WEBHOOK_URL"
            NGROK_SETUP_SUCCESS=true
            break
        else
            RETRY_COUNT=$((RETRY_COUNT + 1))
            if [ $((RETRY_COUNT % 3)) -eq 0 ]; then
                print_info "Waiting for ngrok URL... (attempt $RETRY_COUNT/$MAX_RETRIES)"
            fi
        fi
    done
    
    if [ -z "$WEBHOOK_URL" ]; then
        print_warning "Could not get ngrok URL automatically after $MAX_RETRIES attempts"
        print_info "Checking ngrok service status..."
        sudo systemctl status iot-gui-ngrok.service --no-pager -l | head -10 || true
        print_info "You can get URL manually: ./get-ngrok-url.sh"
        NGROK_SETUP_SUCCESS=false
    fi
else
    print_warning "setup-ngrok.sh not found"
    print_info "You can set up ngrok manually or use cron fallback"
    print_info "Cron fallback: ./setup-cron-fallback.sh"
fi

echo ""

# ============================================================================
# Step 13: Create GitHub Webhook Automatically
# ============================================================================
print_step "Step 13: Creating GitHub Webhook"

WEBHOOK_CREATED=false

# Check if we have webhook URL and can create webhook
if [ -n "$WEBHOOK_URL" ] && [ -f "$PROJECT_DIR/create-github-webhook.sh" ]; then
    print_info "Attempting to create GitHub webhook automatically..."
    chmod +x "$PROJECT_DIR/create-github-webhook.sh"
    
    # Check for GitHub token: environment variable, .github_token file, or default
    if [ -z "$GITHUB_TOKEN" ]; then
        # Check for token file in project directory
        if [ -f "$PROJECT_DIR/.github_token" ]; then
            GITHUB_TOKEN=$(cat "$PROJECT_DIR/.github_token" 2>/dev/null | tr -d '\n\r ')
            if [ -n "$GITHUB_TOKEN" ]; then
                print_info "Using GitHub token from .github_token file"
            fi
        fi
    fi
    
    # Check if GitHub token is provided
    if [ -n "$GITHUB_TOKEN" ]; then
        print_info "Using GitHub token from environment variable"
        WEBHOOK_RESULT=$(GITHUB_TOKEN="$GITHUB_TOKEN" NON_INTERACTIVE=1 "$PROJECT_DIR/create-github-webhook.sh" 2>&1)
        if echo "$WEBHOOK_RESULT" | grep -qi "successfully\|created\|updated"; then
            WEBHOOK_CREATED=true
            print_success "GitHub webhook created/updated successfully!"
        else
            print_warning "Webhook creation result unclear"
            echo "$WEBHOOK_RESULT" | tail -5
            print_info "Checking if webhook exists..."
            # Try to verify webhook exists
            EXISTING_WEBHOOKS=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                "https://api.github.com/repos/$GITHUB_USER/$REPO_NAME/hooks" 2>/dev/null)
            if echo "$EXISTING_WEBHOOKS" | grep -q "$WEBHOOK_URL"; then
                WEBHOOK_CREATED=true
                print_success "Webhook already exists and points to correct URL!"
            else
                print_warning "Webhook may not have been created"
            fi
        fi
    elif [ -f "$PROJECT_DIR/.github_token" ]; then
        GITHUB_TOKEN=$(cat "$PROJECT_DIR/.github_token" 2>/dev/null)
        if [ -n "$GITHUB_TOKEN" ]; then
            print_info "Using GitHub token from .github_token file"
            WEBHOOK_RESULT=$(GITHUB_TOKEN="$GITHUB_TOKEN" NON_INTERACTIVE=1 "$PROJECT_DIR/create-github-webhook.sh" 2>&1)
            if echo "$WEBHOOK_RESULT" | grep -qi "successfully\|created\|updated"; then
                WEBHOOK_CREATED=true
                print_success "GitHub webhook created/updated successfully!"
            else
                print_warning "Failed to create webhook automatically"
                print_info "You can create it manually: ./create-github-webhook.sh"
            fi
        else
            print_warning "GitHub token file exists but is empty"
            print_info "To create webhook automatically:"
            print_info "  1. Get token: https://github.com/settings/tokens"
            print_info "  2. Save to: echo 'your_token' > .github_token"
            print_info "  3. Re-run this step or: ./create-github-webhook.sh"
        fi
    else
        print_warning "GitHub token not provided - webhook creation skipped"
        print_info "To enable automatic webhook creation:"
        print_info "  1. Get token: https://github.com/settings/tokens (scope: repo)"
        print_info "  2. Set: export GITHUB_TOKEN=your_token"
        print_info "  3. Or save: echo 'your_token' > .github_token"
        print_info "  4. Then run: ./create-github-webhook.sh"
        print_info ""
        print_info "Or create webhook manually at:"
        print_info "  https://github.com/$GITHUB_USER/$REPO_NAME/settings/hooks"
        print_info "  URL: $WEBHOOK_URL"
        print_info "  Secret: $WEBHOOK_SECRET"
    fi
else
    if [ -z "$WEBHOOK_URL" ]; then
        print_warning "Webhook URL not available - cannot create webhook"
        print_info "Make sure ngrok is running and get URL: ./get-ngrok-url.sh"
    else
        print_warning "create-github-webhook.sh not found"
        print_info "Create webhook manually at: https://github.com/$GITHUB_USER/$REPO_NAME/settings/hooks"
    fi
fi

echo ""

# ============================================================================
# Step 14: Test the setup
# ============================================================================
print_step "Step 14: Testing Setup"

if [ -f "$PROJECT_DIR/test-deployment.sh" ]; then
    print_info "Running deployment test..."
    chmod +x "$PROJECT_DIR/test-deployment.sh"
    "$PROJECT_DIR/test-deployment.sh" || {
        print_warning "Some tests failed - review the output above"
    }
else
    print_warning "test-deployment.sh not found (skipping automated test)"
fi

# Test webhook endpoint
print_info "Testing webhook endpoint..."
if curl -s http://localhost:$WEBHOOK_PORT/health >/dev/null 2>&1; then
    print_success "Webhook listener is responding"
else
    print_warning "Webhook listener may not be running"
    print_info "Start service: sudo systemctl start iot-gui-webhook.service"
fi
echo ""

# ============================================================================
# Step 15: Start the application
# ============================================================================
print_step "Step 15: Starting Application"

APP_FILE="$PROJECT_DIR/iot_pubsub_gui.py"
PID_FILE="$PROJECT_DIR/app.pid"
LOG_DIR="$PROJECT_DIR/logs"
APP_STARTED=false

if [ ! -f "$APP_FILE" ]; then
    print_warning "Application file not found: $APP_FILE"
    print_info "Skipping application start"
else
    print_info "Starting IoT Pub/Sub GUI application..."
    
    # Check if application is already running
    if pgrep -f "iot_pubsub_gui.py" >/dev/null 2>&1; then
        print_info "Application is already running"
        print_info "Stopping existing instance..."
        pkill -f "iot_pubsub_gui.py" || true
        sleep 2
    fi
    
    # Activate virtual environment if not already activated
    if [ -z "$VIRTUAL_ENV" ] || [ "$VIRTUAL_ENV" != "$VENV_DIR" ]; then
        source "$VENV_DIR/bin/activate"
    fi
    
    # Check if DISPLAY is set (for GUI)
    if [ -z "$DISPLAY" ]; then
        # Try to set DISPLAY if in desktop session
        if [ -n "$XDG_SESSION_ID" ] || [ -n "$WAYLAND_DISPLAY" ]; then
            export DISPLAY=:0 2>/dev/null || true
            print_info "Set DISPLAY=:0 for GUI"
        else
            print_warning "DISPLAY not set - GUI may not work"
            print_warning "If running via SSH, use: ssh -X pi@raspberrypi-ip"
        fi
    fi
    
    # Start the application in background
    print_info "Launching application in background..."
    
    # Create log directory if needed
    mkdir -p "$LOG_DIR"
    
    # Use Python from venv (explicit path for reliability)
    VENV_PYTHON="$VENV_DIR/bin/python"
    if [ ! -f "$VENV_PYTHON" ]; then
        print_error "Python not found in virtual environment: $VENV_PYTHON"
        APP_STARTED=false
    else
        # Start application with nohup using venv Python
        print_info "Using Python from venv: $VENV_PYTHON"
        nohup "$VENV_PYTHON" "$APP_FILE" >> "$LOG_DIR/app.log" 2>&1 &
        APP_PID=$!
        
        # Save PID to file
        echo "$APP_PID" > "$PID_FILE"
        
        # Wait a moment to check if process started successfully
        sleep 2
        
        if kill -0 "$APP_PID" 2>/dev/null; then
            print_success "Application started successfully (PID: $APP_PID)"
            print_info "Application logs: $LOG_DIR/app.log"
            print_info "PID file: $PID_FILE"
            APP_STARTED=true
        else
            print_warning "Application may not have started correctly"
            print_info "Check logs: $LOG_DIR/app.log"
            print_info "Check if all dependencies are installed"
            APP_STARTED=false
        fi
    fi
fi

# ============================================================================
# Summary
# ============================================================================
print_step "Setup Complete!"

echo ""
print_success "Deployment system setup is complete!"
echo ""
print_info "Summary:"
echo "  ✓ System dependencies installed"
echo "  ✓ Repository cloned"
echo "  ✓ Virtual environment configured"
echo "  ✓ Python dependencies installed"
echo "  ✓ SSH key generated and configured"
echo "  ✓ Git repository configured"
echo "  ✓ Webhook secret generated"
echo "  ✓ Scripts made executable"
if [ "$SERVICE_INSTALLED" = true ]; then
    echo "  ✓ Webhook listener service installed and running"
fi
if [ "$NGROK_SETUP_SUCCESS" = true ]; then
    echo "  ✓ ngrok tunnel configured and running"
fi
if [ "$WEBHOOK_CREATED" = true ]; then
    echo "  ✓ GitHub webhook created"
fi
if [ "$APP_STARTED" = true ]; then
    echo "  ✓ Application started"
fi
echo ""
print_info "Project Directory: $PROJECT_DIR"
echo ""
print_info "Next Steps (if not completed automatically):"
echo ""
if [ "$NGROK_SETUP_SUCCESS" != true ]; then
    echo "1. Set up ngrok tunnel:"
    echo "   NGROK_AUTHTOKEN=your_token ./setup-ngrok.sh"
    echo ""
fi
if [ "$WEBHOOK_CREATED" != true ]; then
    echo "2. Create GitHub webhook:"
    if [ -n "$WEBHOOK_URL" ]; then
        echo "   GITHUB_TOKEN=your_token ./create-github-webhook.sh"
        echo "   Or manually: https://github.com/$GITHUB_USER/$REPO_NAME/settings/hooks"
        echo "   URL: $WEBHOOK_URL"
    else
        echo "   First get webhook URL: ./get-ngrok-url.sh"
        echo "   Then: GITHUB_TOKEN=your_token ./create-github-webhook.sh"
    fi
    echo ""
fi
if [ -z "$SSH_KEY_ADDED" ] || [ "$SSH_KEY_ADDED" != true ]; then
    echo "3. Add SSH public key to GitHub (if not done already):"
    echo "   https://github.com/$GITHUB_USER/$REPO_NAME/settings/keys"
    echo "   Public key: $(cat ~/.ssh/id_ed25519_iot_gui.pub 2>/dev/null || echo 'Run setup-ssh-key.sh first')"
    echo ""
fi
if [ "$SERVICE_INSTALLED" = true ]; then
    echo "5. Check services status:"
    echo "   sudo systemctl status iot-gui-webhook.service"
    echo "   sudo systemctl status iot-gui-ngrok.service"
    echo ""
    echo "6. View logs:"
    echo "   sudo journalctl -u iot-gui-webhook.service -f"
    echo "   sudo journalctl -u iot-gui-ngrok.service -f"
    echo ""
fi
echo "7. Application status:"
if [ "$APP_STARTED" = true ] && [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
    echo "   Application is running (PID: $(cat "$PID_FILE"))"
    echo "   View logs: tail -f $LOG_DIR/app.log"
else
    echo "   Application may not be running"
    echo "   Start manually: cd $PROJECT_DIR && source venv/bin/activate && python iot_pubsub_gui.py"
fi
echo ""
echo "7. Test webhook trigger:"
echo "   Make a change to your repo and push to main branch"
echo "   The webhook should automatically trigger update-and-restart.sh"
echo "   Check logs: sudo journalctl -u iot-gui-webhook.service -f"
echo ""
echo "8. Test manual update:"
echo "   cd $PROJECT_DIR"
echo "   ./update-and-restart.sh"
echo ""
echo "9. Test webhook endpoints:"
echo "   Local health: curl http://localhost:$WEBHOOK_PORT/health"
if [ -n "$WEBHOOK_URL" ]; then
    echo "   Public webhook: $WEBHOOK_URL"
    echo "   Test: curl -X POST $WEBHOOK_URL (will fail without GitHub signature)"
fi
echo ""
print_info "Webhook secret saved to: $SECRET_FILE"
print_info "Documentation: See DEPLOYMENT_SETUP.md for detailed instructions"
echo ""
# Final verification and summary
echo ""
print_step "Final Verification"

ALL_SYSTEMS_GO=true

# Check webhook service
if [ "$SERVICE_INSTALLED" = true ]; then
    if sudo systemctl is-active --quiet iot-gui-webhook.service 2>/dev/null; then
        print_success "✓ Webhook listener service is running"
    else
        print_warning "✗ Webhook listener service is not running"
        print_info "   Start with: sudo systemctl start iot-gui-webhook.service"
        ALL_SYSTEMS_GO=false
    fi
else
    print_warning "✗ Webhook listener service not installed"
    ALL_SYSTEMS_GO=false
fi

# Check ngrok
if [ "$NGROK_SETUP_SUCCESS" = true ] && [ -n "$WEBHOOK_URL" ]; then
    if curl -s http://localhost:4040/api/tunnels >/dev/null 2>&1; then
        print_success "✓ ngrok tunnel is active"
        print_info "   Public URL: $WEBHOOK_URL"
    else
        print_warning "✗ ngrok tunnel may not be running"
        print_info "   Check: sudo systemctl status iot-gui-ngrok.service"
        ALL_SYSTEMS_GO=false
    fi
else
    print_warning "✗ ngrok tunnel not configured"
    ALL_SYSTEMS_GO=false
fi

# Check webhook
if [ "$WEBHOOK_CREATED" = true ]; then
    print_success "✓ GitHub webhook created"
else
    print_warning "✗ GitHub webhook not created"
    if [ -n "$WEBHOOK_URL" ]; then
        print_info "   Create with: GITHUB_TOKEN=your_token ./create-github-webhook.sh"
        print_info "   Or manually: https://github.com/$GITHUB_USER/$REPO_NAME/settings/hooks"
    fi
    ALL_SYSTEMS_GO=false
fi

# Check application
if [ "$APP_STARTED" = true ]; then
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
        print_success "✓ Python application is running"
        print_info "   PID: $(cat "$PID_FILE")"
    else
        print_warning "✗ Python application may not be running"
        print_info "   Check logs: tail -f $LOG_DIR/app.log"
        ALL_SYSTEMS_GO=false
    fi
else
    print_warning "✗ Python application not started"
    ALL_SYSTEMS_GO=false
fi

echo ""
if [ "$ALL_SYSTEMS_GO" = true ]; then
    print_success "🎉 All systems operational! Ready for automated deployments!"
    echo ""
    print_info "Complete Flow:"
    echo "  1. Push/merge code to main branch on GitHub"
    echo "  2. GitHub sends webhook POST to: $WEBHOOK_URL"
    echo "  3. Webhook listener receives and verifies request"
    echo "  4. update-and-restart.sh is triggered automatically"
    echo "  5. Code is pulled from GitHub"
    echo "  6. Dependencies are updated"
    echo "  7. Python app is restarted with new code"
    echo ""
    print_info "Test it: Make a small change, commit, and push to main!"
else
    print_warning "Some components need attention (see above)"
    echo ""
    print_info "Next Steps (if not completed automatically):"
    echo ""
    if [ "$NGROK_SETUP_SUCCESS" != true ]; then
        echo "1. Set up ngrok tunnel:"
        echo "   ./setup-ngrok.sh"
        echo ""
    fi
    if [ "$WEBHOOK_CREATED" != true ]; then
        echo "2. Create GitHub webhook:"
        if [ -n "$WEBHOOK_URL" ]; then
            echo "   GITHUB_TOKEN=your_token ./create-github-webhook.sh"
            echo "   Or manually: https://github.com/$GITHUB_USER/$REPO_NAME/settings/hooks"
            echo "   URL: $WEBHOOK_URL"
            echo "   Secret: $WEBHOOK_SECRET"
        else
            echo "   First get webhook URL: ./get-ngrok-url.sh"
            echo "   Then: GITHUB_TOKEN=your_token ./create-github-webhook.sh"
        fi
        echo ""
    fi
    if [ -z "$SSH_KEY_ADDED" ] || [ "$SSH_KEY_ADDED" != true ]; then
        echo "3. Add SSH public key to GitHub (if not done already):"
        echo "   https://github.com/$GITHUB_USER/$REPO_NAME/settings/keys"
        echo "   Public key: $(cat ~/.ssh/id_ed25519_iot_gui.pub 2>/dev/null || echo 'Run setup-ssh-key.sh first')"
        echo ""
    fi
    if [ "$ALL_SYSTEMS_GO" != true ]; then
        echo "4. Test webhook trigger (after setup complete):"
        echo "   Make a change to your repo and push to main branch"
        echo "   The webhook should automatically trigger update-and-restart.sh"
        echo "   Check logs: sudo journalctl -u iot-gui-webhook.service -f"
        echo ""
        echo "5. Test manual update:"
        echo "   cd $PROJECT_DIR"
        echo "   ./update-and-restart.sh"
        echo ""
        echo "6. Test webhook endpoints:"
        echo "   Local health: curl http://localhost:$WEBHOOK_PORT/health"
        if [ -n "$WEBHOOK_URL" ]; then
            echo "   Public webhook: $WEBHOOK_URL"
            echo "   Test: curl -X POST $WEBHOOK_URL (will fail without GitHub signature)"
        fi
        echo ""
    fi
fi

print_success "Setup complete! Happy deploying! 🚀"
echo ""
