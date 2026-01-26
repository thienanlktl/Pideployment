#!/bin/bash
# ============================================================================
# ngrok Setup for GitHub Webhooks
# ============================================================================
# This script sets up ngrok to create a tunnel from Pi to internet
# No router configuration needed!
#
# Usage:
#   chmod +x setup-ngrok.sh
#   ./setup-ngrok.sh [authtoken]
#
#   Or with environment variable:
#   NGROK_AUTHTOKEN=your_token ./setup-ngrok.sh
#
#   Or interactive (will prompt for token):
#   ./setup-ngrok.sh
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

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$SCRIPT_DIR}"

WEBHOOK_PORT="${WEBHOOK_PORT:-9000}"
NGROK_CONFIG_DIR="$HOME/.config/ngrok"
NGROK_CONFIG_FILE="$NGROK_CONFIG_DIR/ngrok.yml"
NGROK_AUTHTOKEN_FILE="$NGROK_CONFIG_DIR/authtoken.txt"

echo ""
print_step "ngrok Setup for GitHub Webhooks"

print_info "ngrok creates a secure tunnel from your Pi to the internet"
print_info "No router configuration needed!"
echo ""

# ============================================================================
# Step 1: Check if ngrok is installed
# ============================================================================
print_step "Step 1: Checking ngrok Installation"

if command -v ngrok >/dev/null 2>&1; then
    NGROK_VERSION=$(ngrok version 2>/dev/null | head -1 || echo "installed")
    print_success "ngrok is already installed: $NGROK_VERSION"
else
    print_info "ngrok is not installed. Installing..."
    
    # Detect architecture
    ARCH=$(uname -m)
    case "$ARCH" in
        armv7l|armv6l)
            NGROK_ARCH="arm"
            ;;
        aarch64|arm64)
            NGROK_ARCH="arm64"
            ;;
        x86_64)
            NGROK_ARCH="amd64"
            ;;
        *)
            print_error "Unsupported architecture: $ARCH"
            print_info "Please install ngrok manually from: https://ngrok.com/download"
            exit 1
            ;;
    esac
    
    print_info "Detected architecture: $ARCH ($NGROK_ARCH)"
    print_info "Downloading ngrok..."
    
    # Download ngrok
    NGROK_URL="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-${NGROK_ARCH}.tgz"
    TEMP_DIR=$(mktemp -d)
    
    if curl -L "$NGROK_URL" -o "$TEMP_DIR/ngrok.tgz" 2>/dev/null; then
        print_success "Downloaded ngrok"
        
        # Extract
        print_info "Extracting ngrok..."
        tar -xzf "$TEMP_DIR/ngrok.tgz" -C "$TEMP_DIR" 2>/dev/null
        
        # Install to /usr/local/bin
        print_info "Installing ngrok..."
        if sudo mv "$TEMP_DIR/ngrok" /usr/local/bin/ngrok; then
            sudo chmod +x /usr/local/bin/ngrok
            print_success "ngrok installed to /usr/local/bin/ngrok"
        else
            # Try user directory
            mkdir -p "$HOME/bin"
            mv "$TEMP_DIR/ngrok" "$HOME/bin/ngrok"
            chmod +x "$HOME/bin/ngrok"
            print_success "ngrok installed to $HOME/bin/ngrok"
            print_info "Add to PATH: export PATH=\"\$HOME/bin:\$PATH\""
        fi
        
        rm -rf "$TEMP_DIR"
    else
        print_error "Failed to download ngrok"
        print_info "Please install manually:"
        print_info "  1. Sign up at https://dashboard.ngrok.com/signup"
        print_info "  2. Download from: https://ngrok.com/download"
        print_info "  3. Extract and move to /usr/local/bin/"
        exit 1
    fi
fi

# ============================================================================
# Step 2: Get ngrok authtoken
# ============================================================================
print_step "Step 2: Configuring ngrok Authentication"

# Check for authtoken from command line argument or environment variable
if [ -n "$1" ]; then
    NGROK_AUTHTOKEN="$1"
    print_info "Using authtoken from command line argument"
elif [ -n "$NGROK_AUTHTOKEN" ]; then
    print_info "Using authtoken from environment variable"
else
    # Check if authtoken already exists
    if [ -f "$NGROK_AUTHTOKEN_FILE" ]; then
        EXISTING_TOKEN=$(cat "$NGROK_AUTHTOKEN_FILE" 2>/dev/null)
        if [ -n "$EXISTING_TOKEN" ]; then
            print_success "Found existing authtoken"
            read -p "Do you want to use existing authtoken? (y/n) " -n 1 -r
            echo ""
            case "$REPLY" in
                [Nn]*)
                    USE_EXISTING=false
                    ;;
                *)
                    USE_EXISTING=true
                    NGROK_AUTHTOKEN="$EXISTING_TOKEN"
                    ;;
            esac
        else
            USE_EXISTING=false
        fi
    else
        USE_EXISTING=false
    fi
    
    if [ "$USE_EXISTING" = false ]; then
        print_info "ngrok requires a free account and authtoken"
        print_info "Get your authtoken from: https://dashboard.ngrok.com/get-started/your-authtoken"
        echo ""
        read -p "Enter your ngrok authtoken: " NGROK_AUTHTOKEN
        
        if [ -z "$NGROK_AUTHTOKEN" ]; then
            print_error "Authtoken cannot be empty"
            exit 1
        fi
    fi
fi

# Create config directory
mkdir -p "$NGROK_CONFIG_DIR"

# Save authtoken
echo "$NGROK_AUTHTOKEN" > "$NGROK_AUTHTOKEN_FILE"
chmod 600 "$NGROK_AUTHTOKEN_FILE"
print_success "Authtoken saved to: $NGROK_AUTHTOKEN_FILE"

# Configure ngrok
print_info "Configuring ngrok..."
if ngrok config add-authtoken "$NGROK_AUTHTOKEN" 2>/dev/null; then
    print_success "ngrok configured successfully"
else
    print_warning "Could not configure via command (may already be configured)"
    print_info "Verifying configuration..."
fi

# ============================================================================
# Step 3: Create ngrok config file
# ============================================================================
print_step "Step 3: Creating ngrok Configuration"

mkdir -p "$NGROK_CONFIG_DIR"

# Create config file
cat > "$NGROK_CONFIG_FILE" << EOF
version: "2"
authtoken: $(cat "$NGROK_AUTHTOKEN_FILE" 2>/dev/null || echo "")
tunnels:
  webhook:
    proto: http
    addr: localhost:$WEBHOOK_PORT
    inspect: false
EOF

print_success "ngrok config created: $NGROK_CONFIG_FILE"

# ============================================================================
# Step 4: Test ngrok
# ============================================================================
print_step "Step 4: Testing ngrok"

print_info "Starting ngrok tunnel (will run in background)..."
print_info "This will create a public URL for your webhook"
echo ""

# Kill existing ngrok if running
pkill -f "ngrok.*webhook" 2>/dev/null || true
sleep 1

# Start ngrok in background
NGROK_LOG="$PROJECT_DIR/ngrok.log"
nohup ngrok start webhook --config "$NGROK_CONFIG_FILE" > "$NGROK_LOG" 2>&1 &
NGROK_PID=$!

print_info "Waiting for ngrok to start..."
sleep 5

# Check if ngrok is running
if kill -0 "$NGROK_PID" 2>/dev/null; then
    print_success "ngrok is running (PID: $NGROK_PID)"
else
    print_error "ngrok failed to start"
    print_info "Check logs: cat $NGROK_LOG"
    exit 1
fi

# Get ngrok URL from API
print_info "Getting ngrok public URL..."
sleep 2
# Get ngrok URL from API (using sed for better compatibility)
NGROK_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | \
    grep -o '"public_url":"https://[^"]*' | head -1 | sed 's/"public_url":"//')

if [ -n "$NGROK_URL" ]; then
    print_success "ngrok tunnel is active!"
    echo ""
    print_info "Public URL:"
    echo "  $NGROK_URL/webhook"
    echo ""
    print_warning "IMPORTANT: Save this URL - you'll need it for GitHub webhook!"
    echo ""
    
    # Save URL to file
    echo "$NGROK_URL/webhook" > "$PROJECT_DIR/.ngrok_url"
    print_success "URL saved to: $PROJECT_DIR/.ngrok_url"
else
    print_warning "Could not get ngrok URL automatically"
    print_info "Check ngrok web interface: http://localhost:4040"
    print_info "Or check logs: cat $NGROK_LOG"
fi

# ============================================================================
# Step 5: Create systemd service for ngrok
# ============================================================================
print_step "Step 5: Creating ngrok Systemd Service"

SERVICE_FILE="$PROJECT_DIR/iot-gui-ngrok.service"
SYSTEMD_SERVICE="/etc/systemd/system/iot-gui-ngrok.service"

print_info "Creating systemd service file..."

# Get current user
CURRENT_USER=$(whoami)

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=ngrok tunnel for GitHub webhooks
After=network.target iot-gui-webhook.service
Requires=iot-gui-webhook.service

[Service]
Type=simple
User=$CURRENT_USER
Group=$CURRENT_USER
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/local/bin/ngrok start webhook --config $NGROK_CONFIG_FILE
Restart=always
RestartSec=10
StandardOutput=append:$PROJECT_DIR/ngrok.log
StandardError=append:$PROJECT_DIR/ngrok.log

[Install]
WantedBy=multi-user.target
EOF

print_success "Service file created: $SERVICE_FILE"

# Install service
print_info "Installing systemd service..."
if sudo cp "$SERVICE_FILE" "$SYSTEMD_SERVICE"; then
    sudo systemctl daemon-reload
    sudo systemctl enable iot-gui-ngrok.service
    print_success "ngrok service installed and enabled"
    print_info "Start with: sudo systemctl start iot-gui-ngrok.service"
else
    print_warning "Failed to install service (may need sudo)"
    print_info "You can start ngrok manually: ngrok start webhook --config $NGROK_CONFIG_FILE"
fi

# ============================================================================
# Summary
# ============================================================================
print_step "ngrok Setup Complete"

echo ""
print_success "ngrok is configured and running!"
echo ""
print_info "Public Webhook URL:"
if [ -n "$NGROK_URL" ]; then
    echo "  $NGROK_URL/webhook"
else
    echo "  (Check: http://localhost:4040 or cat $PROJECT_DIR/.ngrok_url)"
fi
echo ""
print_info "Next Steps:"
echo "  1. Copy the webhook URL above"
echo "  2. Go to: https://github.com/thienanlktl/Pideployment/settings/hooks"
echo "  3. Add webhook with:"
echo "     - Payload URL: $NGROK_URL/webhook (or from .ngrok_url file)"
echo "     - Secret: (from .webhook_secret file)"
echo "     - Events: Just the push event"
echo ""
print_info "To get webhook URL later:"
echo "  ./get-ngrok-url.sh"
echo ""
print_info "To view ngrok dashboard:"
echo "  http://localhost:4040"
echo ""
print_success "Setup complete! No router configuration needed! 🎉"
echo ""

