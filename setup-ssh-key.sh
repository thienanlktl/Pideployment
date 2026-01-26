#!/bin/bash
# ============================================================================
# Setup SSH Key for GitHub Deployment
# ============================================================================
# This script generates an ed25519 SSH key pair for GitHub deployment
# and displays the public key for adding to GitHub as a Deploy Key
#
# Usage:
#   chmod +x setup-ssh-key.sh
#   ./setup-ssh-key.sh
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

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Configuration
SSH_DIR="$HOME/.ssh"
KEY_NAME="id_ed25519_iot_gui"
KEY_PATH="$SSH_DIR/$KEY_NAME"
KEY_COMMENT="iot-gui-deploy@raspberrypi"
GITHUB_USER="thienanlk"
REPO_NAME="iot_pubsub_gui"

echo ""
echo "============================================================================"
echo "GitHub SSH Key Setup for IoT Pub/Sub GUI Deployment"
echo "============================================================================"
echo ""

# ============================================================================
# Step 1: Create .ssh directory if it doesn't exist
# ============================================================================
print_info "Step 1: Checking SSH directory..."

if [ ! -d "$SSH_DIR" ]; then
    print_info "Creating .ssh directory..."
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    print_success "SSH directory created"
else
    print_info "SSH directory exists: $SSH_DIR"
fi

# ============================================================================
# Step 2: Check if key already exists
# ============================================================================
print_info "Step 2: Checking for existing key..."

if [ -f "$KEY_PATH" ]; then
    print_warning "SSH key already exists: $KEY_PATH"
    echo ""
    read -p "Do you want to overwrite it? (y/n) " -n 1 -r
    echo ""
    
    case "$REPLY" in
        [Yy]*)
            print_info "Removing existing key..."
            rm -f "$KEY_PATH" "$KEY_PATH.pub"
            ;;
        *)
            print_info "Using existing key..."
            KEY_EXISTS=true
            ;;
    esac
else
    KEY_EXISTS=false
fi

# ============================================================================
# Step 3: Generate SSH key
# ============================================================================
if [ "$KEY_EXISTS" = false ]; then
    print_info "Step 3: Generating new SSH key pair..."
    
    # Generate ed25519 key without passphrase (for automation)
    ssh-keygen -t ed25519 \
        -C "$KEY_COMMENT" \
        -f "$KEY_PATH" \
        -N "" \
        -q
    
    print_success "SSH key pair generated"
else
    print_info "Step 3: Using existing SSH key"
fi

# ============================================================================
# Step 4: Set proper permissions
# ============================================================================
print_info "Step 4: Setting key permissions..."

chmod 600 "$KEY_PATH"
chmod 644 "$KEY_PATH.pub"

print_success "Key permissions set correctly"

# ============================================================================
# Step 5: Configure SSH config for GitHub
# ============================================================================
print_info "Step 5: Configuring SSH for GitHub..."

SSH_CONFIG="$SSH_DIR/config"
GITHUB_HOST="github.com"
CONFIG_ENTRY="Host github.com-iot-gui
    HostName github.com
    User git
    IdentityFile $KEY_PATH
    IdentitiesOnly yes
"

# Check if config entry already exists
if [ -f "$SSH_CONFIG" ] && grep -q "Host github.com-iot-gui" "$SSH_CONFIG" 2>/dev/null; then
    print_info "SSH config entry already exists"
else
    print_info "Adding SSH config entry..."
    
    # Create config file if it doesn't exist
    if [ ! -f "$SSH_CONFIG" ]; then
        touch "$SSH_CONFIG"
        chmod 600 "$SSH_CONFIG"
    fi
    
    # Append config entry
    echo "" >> "$SSH_CONFIG"
    echo "# GitHub Deploy Key for IoT Pub/Sub GUI" >> "$SSH_CONFIG"
    echo "$CONFIG_ENTRY" >> "$SSH_CONFIG"
    
    print_success "SSH config updated"
fi

# ============================================================================
# Step 6: Display public key
# ============================================================================
echo ""
echo "============================================================================"
echo "PUBLIC KEY - Add this to GitHub as a Deploy Key"
echo "============================================================================"
echo ""
print_success "Your public key is:"
echo ""
cat "$KEY_PATH.pub"
echo ""
echo "============================================================================"
echo ""

# ============================================================================
# Step 7: Instructions
# ============================================================================
print_info "Next steps:"
echo ""
echo "1. Copy the public key above (it starts with 'ssh-ed25519')"
echo ""
echo "2. Go to your GitHub repository:"
echo "   https://github.com/$GITHUB_USER/$REPO_NAME/settings/keys"
echo ""
echo "3. Click 'Add deploy key'"
echo ""
echo "4. Paste the public key and give it a title (e.g., 'Raspberry Pi Deploy Key')"
echo ""
echo "5. Check 'Allow write access' if you want to push changes (optional)"
echo "   For read-only access, leave it unchecked"
echo ""
echo "6. Click 'Add key'"
echo ""
echo "7. Test the connection:"
echo "   ssh -T git@github.com-iot-gui"
echo ""
echo "8. Update your git remote to use the SSH URL:"
echo "   cd ~/PublishDemo"
echo "   git remote set-url origin git@github.com-iot-gui:$GITHUB_USER/$REPO_NAME.git"
echo "   OR"
echo "   git remote set-url origin git@github.com:$GITHUB_USER/$REPO_NAME.git"
echo ""

# ============================================================================
# Step 8: Test connection (optional)
# ============================================================================
read -p "Do you want to test the SSH connection to GitHub now? (y/n) " -n 1 -r
echo ""

case "$REPLY" in
    [Yy]*)
        print_info "Testing SSH connection to GitHub..."
        
        # Test with the specific key
        if ssh -i "$KEY_PATH" -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
            print_success "SSH connection test successful!"
        else
            print_warning "SSH connection test completed (this is normal if key not yet added to GitHub)"
            print_info "After adding the key to GitHub, test again with:"
            echo "  ssh -i $KEY_PATH -T git@github.com"
        fi
        ;;
    *)
        print_info "Skipping connection test"
        ;;
esac

echo ""
print_success "SSH key setup complete!"
echo ""

