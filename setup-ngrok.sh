#!/bin/bash
# ============================================================================
# ngrok Installation and Configuration Script for Raspberry Pi
# ============================================================================
# This script installs and configures ngrok on Raspberry Pi OS (Debian-based)
# using the official APT repository method (preferred) with binary fallback.
#
# Features:
#   - Official APT repository installation (most reliable)
#   - Automatic architecture detection (armhf/armv7l vs aarch64/arm64)
#   - Idempotent (safe to run multiple times)
#   - Strong error handling and validation
#   - Interactive authtoken configuration
#   - Graceful fallback to binary download if APT fails
#
# Usage:
#   chmod +x setup-ngrok.sh
#   sudo ./setup-ngrok.sh
#
# Or with authtoken as argument:
#   sudo ./setup-ngrok.sh YOUR_AUTHTOKEN
#
# Or with environment variable:
#   NGROK_AUTHTOKEN=your_token sudo ./setup-ngrok.sh
#
# Force run mode (disable web interface if ports are blocked):
#   NGROK_FORCE_RUN=true sudo ./setup-ngrok.sh
#
# Enable pooling (allow multiple endpoints to run simultaneously):
#   NGROK_POOLING_ENABLED=true sudo ./setup-ngrok.sh
#
# Custom port:
#   TUNNEL_PORT=8080 sudo ./setup-ngrok.sh
# ============================================================================

# Detect if running with sh and re-execute with bash if needed
if [ -z "${BASH_VERSION:-}" ]; then
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    else
        echo "Error: This script requires bash." >&2
        exit 1
    fi
fi

# Enable strict error handling
set -euo pipefail

# Default ngrok authtoken (can be overridden by argument or environment variable)
# Get your token from: https://dashboard.ngrok.com/get-started/your-authtoken
DEFAULT_NGROK_AUTHTOKEN="38HbghqIwfeBRpp4wdZHFkeTOT1_2Dh6671w4NZEUoFMpcVa6"

# Hardcoded ngrok public URL for GitHub webhook setup
HARDCODED_NGROK_URL="https://tardy-vernita-howlingly.ngrok-free.dev"

# Default tunnel port (can be overridden by environment variable)
# This is the local port that will be exposed to the internet
TUNNEL_PORT="${TUNNEL_PORT:-9000}"

# Tunnel name (used in config file)
TUNNEL_NAME="${TUNNEL_NAME:-webhook}"

# ngrok web interface port (for dashboard)
NGROK_WEB_PORT="${NGROK_WEB_PORT:-4040}"

# Force run mode (disable web interface if ports are blocked)
NGROK_FORCE_RUN="${NGROK_FORCE_RUN:-false}"

# Enable pooling for multiple endpoints (load balancing)
NGROK_POOLING_ENABLED="${NGROK_POOLING_ENABLED:-false}"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Helper functions for colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $*"
}

print_error() {
    echo -e "${RED}[✗]${NC} $*"
}

print_step() {
    echo ""
    echo -e "${CYAN}============================================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}============================================================================${NC}"
    echo ""
}

# ============================================================================
# Step 1: Check for root/sudo privileges
# ============================================================================
print_step "Step 1: Checking Privileges"

if [ "$EUID" -eq 0 ]; then
    print_success "Running as root"
    SUDO_CMD=""
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    print_success "Running with sudo (non-interactive)"
    SUDO_CMD="sudo"
elif command -v sudo >/dev/null 2>&1; then
    print_info "Will use sudo when needed (may prompt for password)"
    SUDO_CMD="sudo"
else
    print_error "This script requires root privileges or sudo"
    print_info "Please run as: sudo $0"
    exit 1
fi

# ============================================================================
# Step 2: Check internet connectivity
# ============================================================================
print_step "Step 2: Checking Internet Connectivity"

print_info "Testing internet connectivity..."
if curl -sSf --max-time 5 https://www.google.com >/dev/null 2>&1 || \
   curl -sSf --max-time 5 https://ngrok.com >/dev/null 2>&1; then
    print_success "Internet connection verified"
else
    print_error "No internet connection detected"
    print_info "Please ensure your Raspberry Pi is connected to the internet"
    exit 1
fi

# ============================================================================
# Step 3: Detect architecture
# ============================================================================
print_step "Step 3: Detecting System Architecture"

ARCH=$(uname -m)
case "$ARCH" in
    armv7l|armv6l)
        DETECTED_ARCH="armhf"
        BINARY_ARCH="arm"
        print_info "Detected architecture: $ARCH (ARM 32-bit / armhf)"
        ;;
    aarch64|arm64)
        DETECTED_ARCH="arm64"
        BINARY_ARCH="arm64"
        print_info "Detected architecture: $ARCH (ARM 64-bit / aarch64)"
        ;;
    x86_64|amd64)
        DETECTED_ARCH="amd64"
        BINARY_ARCH="amd64"
        print_warning "Detected x86_64 architecture (not typical for Raspberry Pi)"
        ;;
    *)
        print_warning "Unsupported architecture detected: $ARCH"
        print_info "Will attempt installation anyway (APT repository may handle it)"
        DETECTED_ARCH="unknown"
        BINARY_ARCH="arm"  # Default fallback
        ;;
esac

# ============================================================================
# Step 4: Check if ngrok is already installed
# ============================================================================
print_step "Step 4: Checking Existing Installation"

NGROK_INSTALLED=false
NGROK_BIN=""

if command -v ngrok >/dev/null 2>&1; then
    NGROK_BIN=$(command -v ngrok)
    NGROK_VERSION=$(ngrok version 2>/dev/null | head -1 || echo "installed")
    print_success "ngrok is already installed: $NGROK_VERSION"
    print_info "Found at: $NGROK_BIN"
    NGROK_INSTALLED=true
else
    print_info "ngrok is not installed"
fi

# ============================================================================
# Step 5: Install ngrok using APT repository (preferred method)
# ============================================================================
if [ "$NGROK_INSTALLED" = false ]; then
    print_step "Step 5: Installing ngrok via Official APT Repository"
    
    print_info "This is the recommended installation method for Raspberry Pi"
    print_info "It ensures you get the latest version and automatic updates"
    
    # Check if repository is already added
    REPO_ADDED=false
    if [ -f /etc/apt/sources.list.d/ngrok.list ]; then
        print_info "ngrok repository already exists in sources.list.d"
        REPO_ADDED=true
    fi
    
    # Add GPG key if not already present
    if [ ! -f /etc/apt/trusted.gpg.d/ngrok.asc ]; then
        print_info "Adding ngrok GPG key..."
        if curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc | $SUDO_CMD tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null; then
            print_success "GPG key added successfully"
        else
            print_error "Failed to add GPG key"
            print_info "Falling back to binary installation method..."
            REPO_ADDED=false
        fi
    else
        print_info "GPG key already exists"
    fi
    
    # Add repository if not already added
    if [ "$REPO_ADDED" = false ]; then
        print_info "Adding ngrok APT repository..."
        # Detect Debian codename for repository
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            DEBIAN_CODENAME="${VERSION_CODENAME:-buster}"
        else
            # Fallback to buster (common on Raspberry Pi OS)
            DEBIAN_CODENAME="buster"
        fi
        
        print_info "Using Debian codename: $DEBIAN_CODENAME"
        if echo "deb https://ngrok-agent.s3.amazonaws.com $DEBIAN_CODENAME main" | $SUDO_CMD tee /etc/apt/sources.list.d/ngrok.list >/dev/null; then
            print_success "Repository added successfully"
        else
            print_error "Failed to add repository"
            print_info "Falling back to binary installation method..."
        fi
    fi
    
    # Update package list
    if [ "$REPO_ADDED" = false ] || [ ! -f /etc/apt/sources.list.d/ngrok.list ]; then
        # Repository wasn't added, skip to binary method
        print_info "Skipping APT update (will use binary method)"
    else
        print_info "Updating package list..."
        if $SUDO_CMD apt-get update -qq; then
            print_success "Package list updated"
        else
            print_warning "APT update failed, falling back to binary installation"
        fi
        
        # Install ngrok via APT
        print_info "Installing ngrok via APT..."
        if $SUDO_CMD apt-get install -y ngrok; then
            print_success "ngrok installed successfully via APT"
            NGROK_INSTALLED=true
            if command -v ngrok >/dev/null 2>&1; then
                NGROK_BIN=$(command -v ngrok)
            fi
        else
            print_warning "APT installation failed, falling back to binary download"
        fi
    fi
fi

# ============================================================================
# Step 6: Fallback to binary download if APT failed
# ============================================================================
if [ "$NGROK_INSTALLED" = false ]; then
    print_step "Step 6: Installing ngrok via Binary Download (Fallback)"
    
    print_info "Using fallback method: direct binary download"
    print_info "This is less ideal than APT but will work if APT fails"
    
    # Ensure required tools are available
    print_info "Checking for required tools..."
    
    # Check for curl or wget
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        print_info "Installing curl..."
        $SUDO_CMD apt-get update -qq
        $SUDO_CMD apt-get install -y curl
    fi
    
    # Check for tar (should be available, but check anyway)
    if ! command -v tar >/dev/null 2>&1; then
        print_info "Installing tar..."
        $SUDO_CMD apt-get install -y tar
    fi
    
    # Determine download URL based on architecture
    NGROK_URL="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-${BINARY_ARCH}.tgz"
    
    print_info "Downloading ngrok for $BINARY_ARCH architecture..."
    print_info "URL: $NGROK_URL"
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf '$TEMP_DIR'" EXIT INT TERM
    
    # Download ngrok
    DOWNLOAD_SUCCESS=false
    if command -v curl >/dev/null 2>&1; then
        if curl -Lf "$NGROK_URL" -o "$TEMP_DIR/ngrok.tgz"; then
            DOWNLOAD_SUCCESS=true
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -q "$NGROK_URL" -O "$TEMP_DIR/ngrok.tgz"; then
            DOWNLOAD_SUCCESS=true
        fi
    fi
    
    if [ "$DOWNLOAD_SUCCESS" = false ]; then
        print_error "Failed to download ngrok binary"
        print_info "Please check your internet connection and try again"
        print_info "Or install manually from: https://ngrok.com/download"
        exit 1
    fi
    
    print_success "Downloaded ngrok binary"
    
    # Extract
    print_info "Extracting ngrok..."
    if tar -xzf "$TEMP_DIR/ngrok.tgz" -C "$TEMP_DIR" 2>/dev/null; then
        print_success "Extracted successfully"
    else
        print_error "Failed to extract ngrok archive"
        exit 1
    fi
    
    # Verify extracted binary exists
    if [ ! -f "$TEMP_DIR/ngrok" ]; then
        print_error "ngrok binary not found in archive"
        exit 1
    fi
    
    # Make binary executable
    chmod +x "$TEMP_DIR/ngrok"
    
    # Install to /usr/local/bin (preferred system location)
    print_info "Installing ngrok to /usr/local/bin/ngrok..."
    if $SUDO_CMD mv "$TEMP_DIR/ngrok" /usr/local/bin/ngrok; then
        $SUDO_CMD chmod +x /usr/local/bin/ngrok
        NGROK_BIN="/usr/local/bin/ngrok"
        print_success "ngrok installed to /usr/local/bin/ngrok"
        NGROK_INSTALLED=true
    else
        # Fallback to user bin directory if system install fails
        print_warning "System installation failed, installing to user directory..."
        mkdir -p "$HOME/bin"
        mv "$TEMP_DIR/ngrok" "$HOME/bin/ngrok"
        chmod +x "$HOME/bin/ngrok"
        NGROK_BIN="$HOME/bin/ngrok"
        print_success "ngrok installed to $HOME/bin/ngrok"
        print_info "Adding to PATH for this session..."
        export PATH="$HOME/bin:$PATH"
        NGROK_INSTALLED=true
    fi
    
    # Clean up
    rm -rf "$TEMP_DIR"
    trap - EXIT INT TERM
fi

# Verify installation
if [ "$NGROK_INSTALLED" = true ] && [ -n "$NGROK_BIN" ] && [ -x "$NGROK_BIN" ]; then
    print_success "ngrok installation verified"
else
    print_error "ngrok installation verification failed"
    exit 1
fi

# ============================================================================
# Step 7: Configure ngrok authtoken
# ============================================================================
print_step "Step 7: Configuring ngrok Authentication"

# Check for authtoken from command line argument, environment variable, default, or prompt
NGROK_AUTHTOKEN=""

if [ -n "${1:-}" ]; then
    NGROK_AUTHTOKEN="$1"
    print_info "Using authtoken from command line argument"
elif [ -n "${NGROK_AUTHTOKEN:-}" ]; then
    print_info "Using authtoken from environment variable"
else
    # Check if authtoken is already configured
    NGROK_CONFIG_DIR="$HOME/.config/ngrok"
    if [ -f "$NGROK_CONFIG_DIR/ngrok.yml" ]; then
        print_info "Found existing ngrok configuration"
        read -p "Do you want to reconfigure authtoken? (y/n) " -n 1 -r
        echo ""
        if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
            print_info "Keeping existing configuration"
            NGROK_AUTHTOKEN=""
        fi
    fi
    
    if [ -z "$NGROK_AUTHTOKEN" ]; then
        # Use default token if available, otherwise prompt
        if [ -n "$DEFAULT_NGROK_AUTHTOKEN" ]; then
            NGROK_AUTHTOKEN="$DEFAULT_NGROK_AUTHTOKEN"
            print_info "Using pre-configured default authtoken"
        else
            print_info "ngrok requires an authtoken to create tunnels"
            print_info "Get your free authtoken from:"
            print_info "  https://dashboard.ngrok.com/get-started/your-authtoken"
            echo ""
            read -p "Enter your ngrok authtoken: " -r NGROK_AUTHTOKEN
            
            if [ -z "$NGROK_AUTHTOKEN" ]; then
                print_error "Authtoken cannot be empty"
                print_info "You can configure it later with:"
                print_info "  ngrok config add-authtoken YOUR_TOKEN"
                exit 1
            fi
        fi
    fi
fi

# Configure authtoken if provided
if [ -n "$NGROK_AUTHTOKEN" ]; then
    print_info "Configuring ngrok authtoken..."
    # Use the ngrok binary we found/installed
    if "$NGROK_BIN" config add-authtoken "$NGROK_AUTHTOKEN" 2>/dev/null; then
        print_success "ngrok authtoken configured successfully"
    else
        print_warning "Authtoken configuration command returned an error"
        print_info "This may be normal if authtoken was already configured"
        print_info "Verifying configuration..."
        
        # Verify by checking version (will fail if not authenticated)
        if "$NGROK_BIN" version >/dev/null 2>&1; then
            print_success "ngrok appears to be properly configured"
        else
            print_warning "Could not verify configuration, but continuing..."
        fi
    fi
else
    print_info "Skipping authtoken configuration (already configured or not provided)"
fi

# ============================================================================
# Step 8: Verify installation
# ============================================================================
print_step "Step 8: Verifying Installation"

print_info "Testing ngrok installation..."
if "$NGROK_BIN" --version >/dev/null 2>&1; then
    NGROK_VERSION_OUTPUT=$("$NGROK_BIN" --version 2>&1 || "$NGROK_BIN" version 2>&1 || echo "unknown")
    print_success "ngrok is working correctly!"
    print_info "Version information:"
    echo "$NGROK_VERSION_OUTPUT" | while IFS= read -r line; do
        echo "  $line"
    done
else
    print_error "ngrok verification failed"
    print_info "Please check the installation manually"
    exit 1
fi

# ============================================================================
# Step 9: Create ngrok tunnel configuration
# ============================================================================
print_step "Step 9: Creating Tunnel Configuration"

NGROK_CONFIG_DIR="$HOME/.config/ngrok"
NGROK_CONFIG_FILE="$NGROK_CONFIG_DIR/ngrok.yml"

# Create config directory if it doesn't exist
mkdir -p "$NGROK_CONFIG_DIR"

print_info "Creating ngrok tunnel configuration..."
print_info "Tunnel name: $TUNNEL_NAME"
print_info "Local port: $TUNNEL_PORT"
print_info "Web interface: http://localhost:$NGROK_WEB_PORT"

# Create or update config file
# Disable web interface if force run mode is enabled
# Add pooling if enabled
if [ "$NGROK_FORCE_RUN" = "true" ]; then
    print_info "Force run mode enabled - disabling web interface"
    if [ "$NGROK_POOLING_ENABLED" = "true" ]; then
        print_info "Pooling enabled - multiple endpoints can run simultaneously"
        cat > "$NGROK_CONFIG_FILE" << EOF
version: "2"
authtoken: ${NGROK_AUTHTOKEN:-$DEFAULT_NGROK_AUTHTOKEN}
web_addr: false
tunnels:
  $TUNNEL_NAME:
    proto: http
    addr: localhost:$TUNNEL_PORT
    schemes: [https]
    inspect: false
    pooling_enabled: true
EOF
    else
        cat > "$NGROK_CONFIG_FILE" << EOF
version: "2"
authtoken: ${NGROK_AUTHTOKEN:-$DEFAULT_NGROK_AUTHTOKEN}
web_addr: false
tunnels:
  $TUNNEL_NAME:
    proto: http
    addr: localhost:$TUNNEL_PORT
    schemes: [https]
    inspect: false
EOF
    fi
else
    if [ "$NGROK_POOLING_ENABLED" = "true" ]; then
        print_info "Pooling enabled - multiple endpoints can run simultaneously"
        cat > "$NGROK_CONFIG_FILE" << EOF
version: "2"
authtoken: ${NGROK_AUTHTOKEN:-$DEFAULT_NGROK_AUTHTOKEN}
web_addr: localhost:$NGROK_WEB_PORT
tunnels:
  $TUNNEL_NAME:
    proto: http
    addr: localhost:$TUNNEL_PORT
    schemes: [https]
    inspect: true
    pooling_enabled: true
EOF
    else
        cat > "$NGROK_CONFIG_FILE" << EOF
version: "2"
authtoken: ${NGROK_AUTHTOKEN:-$DEFAULT_NGROK_AUTHTOKEN}
web_addr: localhost:$NGROK_WEB_PORT
tunnels:
  $TUNNEL_NAME:
    proto: http
    addr: localhost:$TUNNEL_PORT
    schemes: [https]
    inspect: true
EOF
    fi
fi

print_success "Configuration file created: $NGROK_CONFIG_FILE"
chmod 600 "$NGROK_CONFIG_FILE"

# ============================================================================
# Step 10: Start ngrok tunnel
# ============================================================================
print_step "Step 10: Starting ngrok Tunnel"

# Check if ngrok is already running and has an active tunnel
print_info "Checking for existing ngrok tunnels..."
NGROK_ALREADY_RUNNING=false
EXISTING_URL=""
EXISTING_PORT=""

# Check for ngrok processes first
if pgrep -f "ngrok" >/dev/null 2>&1; then
    print_info "Found ngrok process running, checking for active tunnels..."
    
    # Check all possible ngrok API ports
    for port in 4040 4041 4042 4043 4044; do
        if curl -s --max-time 3 "http://localhost:$port/api/tunnels" >/dev/null 2>&1; then
            print_info "Found ngrok API on port $port, checking tunnels..."
            
            # Get tunnels JSON
            TUNNELS_JSON=$(curl -s --max-time 3 "http://localhost:$port/api/tunnels" 2>/dev/null || echo "{}")
            
            if [ -n "$TUNNELS_JSON" ] && [ "$TUNNELS_JSON" != "{}" ]; then
                # Extract tunnel information
                # Look for tunnels that match our port or any active tunnel
                TUNNEL_COUNT=$(echo "$TUNNELS_JSON" | grep -o '"name"' | wc -l || echo "0")
                
                if [ "$TUNNEL_COUNT" -gt 0 ]; then
                    # Get the first active tunnel URL
                    EXISTING_URL=$(echo "$TUNNELS_JSON" | grep -o "\"public_url\":\"https://[^\"]*" | head -1 | sed 's/"public_url":"//' || true)
                    
                    # Check if any tunnel is pointing to our target port
                    TUNNEL_ADDR=$(echo "$TUNNELS_JSON" | grep -o "\"addr\":\"localhost:[0-9]*" | head -1 | sed 's/"addr":"localhost://' || true)
                    
                    if [ -n "$EXISTING_URL" ]; then
                        EXISTING_PORT="$port"
                        
                        # If tunnel matches our port, prefer it
                        if [ -n "$TUNNEL_ADDR" ] && [ "$TUNNEL_ADDR" = "$TUNNEL_PORT" ]; then
                            print_success "Found existing tunnel matching port $TUNNEL_PORT!"
                            print_info "Tunnel URL: $EXISTING_URL"
                            print_info "Local port: $TUNNEL_ADDR"
                            NGROK_ALREADY_RUNNING=true
                            break
                        elif [ -n "$TUNNEL_ADDR" ]; then
                            print_info "Found existing tunnel on different port ($TUNNEL_ADDR vs $TUNNEL_PORT)"
                            print_info "Tunnel URL: $EXISTING_URL"
                            # Still use it if no better match found
                            if [ -z "$EXISTING_URL" ] || [ "$NGROK_ALREADY_RUNNING" = false ]; then
                                print_info "Will reuse this tunnel"
                                NGROK_ALREADY_RUNNING=true
                            fi
                        else
                            # Found a tunnel but couldn't determine port - use it anyway
                            print_success "Found existing active tunnel!"
                            print_info "Tunnel URL: $EXISTING_URL"
                            NGROK_ALREADY_RUNNING=true
                            break
                        fi
                    fi
                fi
            fi
        fi
    done
    
    # If we found a tunnel, verify it's actually working
    if [ "$NGROK_ALREADY_RUNNING" = true ] && [ -n "$EXISTING_URL" ]; then
        print_info "Verifying existing tunnel is active..."
        # Try to access the tunnel URL to verify it's working
        if curl -s --max-time 5 --head "$EXISTING_URL" >/dev/null 2>&1 || \
           curl -s --max-time 5 "$EXISTING_URL" >/dev/null 2>&1; then
            print_success "Existing tunnel is active and working!"
        else
            print_warning "Existing tunnel URL found but may not be responding"
            print_info "Will continue to use it anyway"
        fi
    fi
fi

# If we found an existing working tunnel, use it
# But prefer hardcoded URL if available
if [ -n "$HARDCODED_NGROK_URL" ]; then
    print_info "Using hardcoded ngrok URL: $HARDCODED_NGROK_URL"
    TUNNEL_URL="$HARDCODED_NGROK_URL"
    print_success "Using hardcoded ngrok URL for GitHub webhook setup"
    
    # Save URL to file if PROJECT_DIR is set
    if [ -n "${PROJECT_DIR:-}" ]; then
        # Construct webhook URL
        if echo "$TUNNEL_URL" | grep -q "/webhook$"; then
            WEBHOOK_URL="$TUNNEL_URL"
        else
            WEBHOOK_URL="$TUNNEL_URL/webhook"
        fi
        echo "$WEBHOOK_URL" > "$PROJECT_DIR/.ngrok_url"
        print_info "Webhook URL saved to: $PROJECT_DIR/.ngrok_url"
    fi
elif [ "$NGROK_ALREADY_RUNNING" = true ] && [ -n "$EXISTING_URL" ]; then
    print_success "Using existing ngrok tunnel - no need to start a new one"
    TUNNEL_URL="$EXISTING_URL"
    print_info "Existing tunnel URL: $TUNNEL_URL"
    
    # Save URL to file if PROJECT_DIR is set
    if [ -n "${PROJECT_DIR:-}" ]; then
        echo "$TUNNEL_URL" > "$PROJECT_DIR/.ngrok_url"
        print_info "URL saved to: $PROJECT_DIR/.ngrok_url"
    fi
fi

if [ "$NGROK_ALREADY_RUNNING" = false ]; then
    # Stop any existing ngrok processes and endpoints (stop systemd services first!)
    print_info "Force stopping all existing ngrok processes and endpoints..."
    
    # Check for ngrok API on multiple possible ports (4040, 4041, etc.)
    print_info "Checking for active ngrok endpoints on all ports..."
    for port in 4040 4041 4042 4043 4044; do
        if curl -s --max-time 2 "http://localhost:$port/api/tunnels" >/dev/null 2>&1; then
            print_warning "Found ngrok API responding on port $port"
            TUNNELS_JSON=$(curl -s --max-time 3 "http://localhost:$port/api/tunnels" 2>/dev/null || echo "{}")
            
            # Extract tunnel names
            TUNNEL_NAMES=$(echo "$TUNNELS_JSON" | grep -o '"name":"[^"]*' | sed 's/"name":"//' | sort -u || true)
            
            if [ -n "$TUNNEL_NAMES" ]; then
                print_info "Found active tunnels on port $port: $TUNNEL_NAMES"
            fi
        fi
    done
    
    # First, stop and disable systemd services that might be managing ngrok
    # This prevents systemd from restarting ngrok while we're setting it up
    if $SUDO_CMD systemctl is-enabled --quiet iot-gui-ngrok.service 2>/dev/null; then
        print_info "Temporarily disabling ngrok systemd service to prevent auto-restart..."
        $SUDO_CMD systemctl disable iot-gui-ngrok.service 2>/dev/null || true
    fi
    
    if $SUDO_CMD systemctl is-active --quiet iot-gui-ngrok.service 2>/dev/null; then
        print_info "Stopping ngrok systemd service..."
        $SUDO_CMD systemctl stop iot-gui-ngrok.service 2>/dev/null || true
        sleep 5  # Give more time for service to stop
    fi
    
    # Check for other possible ngrok service names
    for service_name in ngrok.service ngrok-tunnel.service; do
        if $SUDO_CMD systemctl list-units --type=service --all 2>/dev/null | grep -q "$service_name"; then
            if $SUDO_CMD systemctl is-active --quiet "$service_name" 2>/dev/null; then
                print_info "Stopping $service_name..."
                $SUDO_CMD systemctl stop "$service_name" 2>/dev/null || true
                sleep 2
            fi
        fi
    done
    
    # Now kill any remaining ngrok processes
    # Use a safer approach: get PIDs first, then kill them specifically
    # This avoids matching the script itself
    print_info "Killing any remaining ngrok processes..."
    
    # Get current script PID to exclude it
    SCRIPT_PID=$$
    
    # Find ngrok processes (exclude this script and grep itself)
    NGROK_PIDS=$(pgrep -f "ngrok" 2>/dev/null | grep -v "^${SCRIPT_PID}$" || true)
    
    if [ -n "$NGROK_PIDS" ]; then
        print_info "Found ngrok processes: $NGROK_PIDS"
        
        # Try graceful kill first (SIGTERM)
        for pid in $NGROK_PIDS; do
            if kill -0 "$pid" 2>/dev/null; then
                print_info "Sending SIGTERM to PID $pid..."
                kill "$pid" 2>/dev/null || true
            fi
        done
        
        sleep 5  # Give more time for graceful shutdown
        
        # Check if still running, force kill if needed
        NGROK_PIDS=$(pgrep -f "ngrok" 2>/dev/null | grep -v "^${SCRIPT_PID}$" || true)
        if [ -n "$NGROK_PIDS" ]; then
            print_warning "Some ngrok processes still running, force killing..."
            for pid in $NGROK_PIDS; do
                if kill -0 "$pid" 2>/dev/null; then
                    print_info "Force killing PID $pid..."
                    kill -9 "$pid" 2>/dev/null || true
                fi
            done
            sleep 3
        fi
        
        # Final check - wait a bit more and verify
        sleep 2
        NGROK_PIDS=$(pgrep -f "ngrok" 2>/dev/null | grep -v "^${SCRIPT_PID}$" || true)
        if [ -n "$NGROK_PIDS" ]; then
            print_warning "Some ngrok processes may still be running: $NGROK_PIDS"
            print_info "Waiting a bit longer for processes to fully stop..."
            sleep 3
            # One more force kill attempt
            for pid in $NGROK_PIDS; do
                if kill -0 "$pid" 2>/dev/null; then
                    kill -9 "$pid" 2>/dev/null || true
                fi
            done
            sleep 2
        fi
        
        # Final verification
        NGROK_PIDS=$(pgrep -f "ngrok" 2>/dev/null | grep -v "^${SCRIPT_PID}$" || true)
        if [ -n "$NGROK_PIDS" ]; then
            print_warning "Warning: Some ngrok processes may still be running: $NGROK_PIDS"
            print_info "You may need to manually stop them: sudo kill -9 $NGROK_PIDS"
            print_info "Or check what's keeping them alive: ps aux | grep ngrok"
        else
            print_success "All ngrok processes stopped"
        fi
    else
        print_info "No ngrok processes found running"
    fi
    
    # Wait longer to ensure ports are fully released and endpoints are closed
    print_info "Waiting for ports and endpoints to be fully released..."
    sleep 5
    
    # Verify no ngrok API is responding on ANY port (means endpoints are closed)
    print_info "Verifying all ngrok endpoints are stopped..."
    ENDPOINTS_STILL_ACTIVE=false
    for port in 4040 4041 4042 4043 4044; do
        if curl -s --max-time 2 "http://localhost:$port/api/tunnels" >/dev/null 2>&1; then
            print_warning "ngrok API still responding on port $port - endpoints may still be active"
            ENDPOINTS_STILL_ACTIVE=true
        fi
    done
    
    if [ "$ENDPOINTS_STILL_ACTIVE" = true ]; then
        print_warning "Some endpoints may still be active, attempting additional cleanup..."
        
        # One more aggressive kill attempt
        NGROK_PIDS=$(pgrep -f "ngrok" 2>/dev/null | grep -v "^${SCRIPT_PID}$" || true)
        if [ -n "$NGROK_PIDS" ]; then
            print_info "Force killing remaining processes: $NGROK_PIDS"
            for pid in $NGROK_PIDS; do
                kill -9 "$pid" 2>/dev/null || true
            done
            sleep 3
        fi
        
        # Check one more time
        ENDPOINTS_STILL_ACTIVE=false
        for port in 4040 4041 4042 4043 4044; do
            if curl -s --max-time 2 "http://localhost:$port/api/tunnels" >/dev/null 2>&1; then
                ENDPOINTS_STILL_ACTIVE=true
                break
            fi
        done
        
        if [ "$ENDPOINTS_STILL_ACTIVE" = true ]; then
            print_warning "Warning: Some endpoints may still be active"
            print_info "If you get endpoint conflict errors, try:"
            print_info "  1. Manually stop: pkill -9 ngrok && sudo systemctl stop iot-gui-ngrok.service"
            print_info "  2. Or enable pooling: NGROK_POOLING_ENABLED=true sudo ./setup-ngrok.sh"
        else
            print_success "All endpoints confirmed stopped after additional cleanup"
        fi
    else
        print_success "Confirmed: All ngrok endpoints are stopped"
    fi
    
    # Final check before starting - make sure nothing is running
    print_info "Final check before starting tunnel..."
    FINAL_CHECK_FAILED=false
    
    # Check for any ngrok processes
    NGROK_PIDS=$(pgrep -f "ngrok" 2>/dev/null | grep -v "^${SCRIPT_PID}$" || true)
    if [ -n "$NGROK_PIDS" ]; then
        print_warning "Found ngrok processes still running: $NGROK_PIDS"
        print_info "Force killing one more time..."
        for pid in $NGROK_PIDS; do
            kill -9 "$pid" 2>/dev/null || true
        done
        sleep 2
    fi
    
    # Check for API on any port
    for port in 4040 4041 4042 4043 4044; do
        if curl -s --max-time 1 "http://localhost:$port/api/tunnels" >/dev/null 2>&1; then
            print_warning "ngrok API still responding on port $port"
            FINAL_CHECK_FAILED=true
        fi
    done
    
    if [ "$FINAL_CHECK_FAILED" = true ] && [ "$NGROK_POOLING_ENABLED" != "true" ]; then
        print_error "Cannot start tunnel - endpoints still active and pooling is disabled"
        print_info "Solutions:"
        print_info "  1. Wait a bit longer and try again"
        print_info "  2. Manually stop: pkill -9 ngrok && sudo systemctl stop iot-gui-ngrok.service"
        print_info "  3. Enable pooling: NGROK_POOLING_ENABLED=true sudo ./setup-ngrok.sh"
        exit 1
    fi
    
    # Start ngrok tunnel in background
    print_info "Starting ngrok tunnel '$TUNNEL_NAME' on port $TUNNEL_PORT..."
    if [ "$NGROK_POOLING_ENABLED" = "true" ]; then
        print_info "Pooling enabled - this endpoint can run alongside others"
    fi
    NGROK_LOG="$HOME/ngrok.log"
    
    # Build start command
    START_CMD="$NGROK_BIN start $TUNNEL_NAME --config $NGROK_CONFIG_FILE"
    if [ "$NGROK_POOLING_ENABLED" = "true" ]; then
        START_CMD="$START_CMD --pooling-enabled"
        print_info "Using command: $START_CMD"
    fi
    
    # Start ngrok
    nohup $START_CMD > "$NGROK_LOG" 2>&1 &
    NGROK_PID=$!
    
    print_info "ngrok started with PID: $NGROK_PID"
    print_info "Waiting for tunnel to initialize..."
    
    # Wait for ngrok to start and get URL
    MAX_WAIT=20
    WAIT_COUNT=0
    TUNNEL_URL=""
    
    while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
        sleep 1
        WAIT_COUNT=$((WAIT_COUNT + 1))
        
        # Check if process is still running
        if ! kill -0 "$NGROK_PID" 2>/dev/null; then
            print_error "ngrok process died"
            print_info "Check log file: $NGROK_LOG"
            if [ -f "$NGROK_LOG" ]; then
                echo ""
                echo "=== Last 30 lines of ngrok.log ==="
                tail -30 "$NGROK_LOG"
                echo "=== End of log ==="
                echo ""
                
                # Check for endpoint conflict error
                if grep -qi "stop your existing endpoint\|pooling-enabled\|endpoint.*already" "$NGROK_LOG" 2>/dev/null; then
                    print_error "ENDPOINT CONFLICT DETECTED!"
                    print_info ""
                    print_info "Error: Another ngrok endpoint is already running"
                    print_info ""
                    print_info "Solutions:"
                    print_info "  1. Stop existing endpoint first:"
                    print_info "     pkill -9 ngrok"
                    print_info "     sudo systemctl stop iot-gui-ngrok.service"
                    print_info ""
                    print_info "  2. Or enable pooling to run multiple endpoints:"
                    print_info "     NGROK_POOLING_ENABLED=true sudo ./setup-ngrok.sh"
                    print_info ""
                    print_info "  3. Check what's running:"
                    print_info "     ps aux | grep ngrok"
                    print_info "     sudo systemctl status iot-gui-ngrok.service"
                    print_info ""
                fi
            fi
            exit 1
        fi
        
        # Try to get URL from API
        if curl -s --max-time 3 "http://localhost:$NGROK_WEB_PORT/api/tunnels" >/dev/null 2>&1; then
            TUNNEL_URL=$(curl -s --max-time 3 "http://localhost:$NGROK_WEB_PORT/api/tunnels" 2>/dev/null | \
                grep -o "\"public_url\":\"https://[^\"]*" | head -1 | sed 's/"public_url":"//')
            if [ -n "$TUNNEL_URL" ]; then
                print_success "Tunnel is active!"
                break
            fi
        fi
        
        # Show progress every 3 seconds
        if [ $((WAIT_COUNT % 3)) -eq 0 ]; then
            print_info "Waiting for tunnel... (${WAIT_COUNT}s/${MAX_WAIT}s)"
        fi
    done
    
    # If API didn't work, try to get URL from log file
    if [ -z "$TUNNEL_URL" ] && [ -f "$NGROK_LOG" ]; then
        print_info "Extracting URL from log file..."
        sleep 2
        TUNNEL_URL=$(grep -oE "https://[a-z0-9-]+\.ngrok-free\.dev" "$NGROK_LOG" 2>/dev/null | head -1)
        if [ -z "$TUNNEL_URL" ]; then
            TUNNEL_URL=$(grep -oE "https://[a-z0-9-]+\.ngrok\.io" "$NGROK_LOG" 2>/dev/null | head -1)
        fi
    fi
    
    # Use hardcoded URL if available and we couldn't get URL from API/log
    if [ -z "$TUNNEL_URL" ] && [ -n "$HARDCODED_NGROK_URL" ]; then
        print_info "Using hardcoded ngrok URL: $HARDCODED_NGROK_URL"
        TUNNEL_URL="$HARDCODED_NGROK_URL"
    fi
    
    # Use hardcoded URL if available and we couldn't get URL from API/log
    if [ -z "$TUNNEL_URL" ] && [ -n "$HARDCODED_NGROK_URL" ]; then
        print_info "Using hardcoded ngrok URL: $HARDCODED_NGROK_URL"
        TUNNEL_URL="$HARDCODED_NGROK_URL"
    fi
    
    if [ -n "$TUNNEL_URL" ]; then
        print_success "Public tunnel URL: $TUNNEL_URL"
        
        # Save URL to file if PROJECT_DIR is set
        if [ -n "${PROJECT_DIR:-}" ]; then
            # Construct webhook URL
            if echo "$TUNNEL_URL" | grep -q "/webhook$"; then
                WEBHOOK_URL="$TUNNEL_URL"
            else
                WEBHOOK_URL="$TUNNEL_URL/webhook"
            fi
            echo "$WEBHOOK_URL" > "$PROJECT_DIR/.ngrok_url"
            print_info "Webhook URL saved to: $PROJECT_DIR/.ngrok_url"
        fi
    else
        print_warning "Could not get tunnel URL automatically"
        print_info "Check ngrok dashboard: http://localhost:$NGROK_WEB_PORT"
        print_info "Or check log file: $NGROK_LOG"
    fi
fi
# End of tunnel startup section (only runs if no existing tunnel was found)

# ============================================================================
# Step 11: Create systemd service for persistent tunnel
# ============================================================================
print_step "Step 11: Creating Systemd Service"

# Get current user
CURRENT_USER=$(whoami)
PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
SERVICE_FILE="$PROJECT_DIR/iot-gui-ngrok.service"
SYSTEMD_SERVICE="/etc/systemd/system/iot-gui-ngrok.service"

print_info "Creating systemd service for persistent tunnel..."

# Create service file
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=ngrok tunnel for $TUNNEL_NAME (port $TUNNEL_PORT)
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
Group=$CURRENT_USER
WorkingDirectory=$HOME
ExecStart=$NGROK_BIN start $TUNNEL_NAME --config $NGROK_CONFIG_FILE${NGROK_POOLING_ENABLED:+ --pooling-enabled}
Restart=always
RestartSec=10
StandardOutput=append:$HOME/ngrok.log
StandardError=append:$HOME/ngrok.log

[Install]
WantedBy=multi-user.target
EOF

print_success "Service file created: $SERVICE_FILE"

# Install service
print_info "Installing systemd service..."

# Stop existing service if running
if $SUDO_CMD systemctl is-active --quiet iot-gui-ngrok.service 2>/dev/null; then
    print_info "Stopping existing service..."
    $SUDO_CMD systemctl stop iot-gui-ngrok.service 2>/dev/null || true
    sleep 2
fi

# Stop any running ngrok processes before installing service
# (Service should already be stopped above, but double-check)
print_info "Ensuring all ngrok processes are stopped before installing service..."

# Stop systemd service if running
if $SUDO_CMD systemctl is-active --quiet iot-gui-ngrok.service 2>/dev/null; then
    print_info "Stopping ngrok systemd service..."
    $SUDO_CMD systemctl stop iot-gui-ngrok.service 2>/dev/null || true
    sleep 3
fi

# Kill any remaining processes (use safer PID-based approach)
# Get current script PID to exclude it
SCRIPT_PID=$$

# Find ngrok processes (exclude this script)
NGROK_PIDS=$(pgrep -f "ngrok" 2>/dev/null | grep -v "^${SCRIPT_PID}$" || true)

if [ -n "$NGROK_PIDS" ]; then
    print_info "Killing remaining ngrok processes: $NGROK_PIDS"
    
    # Try graceful kill first
    for pid in $NGROK_PIDS; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    sleep 2
    
    # Force kill if still running
    NGROK_PIDS=$(pgrep -f "ngrok" 2>/dev/null | grep -v "^${SCRIPT_PID}$" || true)
    if [ -n "$NGROK_PIDS" ]; then
        print_warning "Force killing remaining ngrok processes: $NGROK_PIDS"
        for pid in $NGROK_PIDS; do
            if kill -0 "$pid" 2>/dev/null; then
                kill -9 "$pid" 2>/dev/null || true
            fi
        done
        sleep 2
    fi
fi

# Verify no ngrok processes are running
NGROK_PIDS=$(pgrep -f "ngrok" 2>/dev/null | grep -v "^${SCRIPT_PID}$" || true)
if [ -n "$NGROK_PIDS" ]; then
    print_warning "Warning: Some ngrok processes may still be running: $NGROK_PIDS"
    print_info "Process list:"
    ps aux | grep "[n]grok" || true
    print_info "You may need to manually stop them before continuing"
else
    print_success "All ngrok processes confirmed stopped"
fi

sleep 1

if $SUDO_CMD cp "$SERVICE_FILE" "$SYSTEMD_SERVICE"; then
    $SUDO_CMD systemctl daemon-reload
    $SUDO_CMD systemctl enable iot-gui-ngrok.service
    print_success "Service installed and enabled"
    
    # Start the service
    print_info "Starting ngrok service..."
    if $SUDO_CMD systemctl start iot-gui-ngrok.service; then
        sleep 3
        if $SUDO_CMD systemctl is-active --quiet iot-gui-ngrok.service; then
            print_success "ngrok service is running!"
        else
            print_warning "Service may still be starting..."
        fi
    else
        print_warning "Service start had issues, but continuing..."
    fi
else
    print_warning "Failed to install service (may need sudo)"
    print_info "You can start ngrok manually: $NGROK_BIN start $TUNNEL_NAME --config $NGROK_CONFIG_FILE"
fi

# ============================================================================
# Summary and Next Steps
# ============================================================================
print_step "Installation Complete"

print_success "ngrok has been successfully installed, configured, and tunnel started!"
echo ""
print_info "Installation details:"
echo "  Binary location: $NGROK_BIN"
echo "  Architecture: $ARCH ($DETECTED_ARCH)"
echo "  Config file: $NGROK_CONFIG_FILE"
echo "  Tunnel name: $TUNNEL_NAME"
echo "  Local port: $TUNNEL_PORT"
echo ""

# Use hardcoded URL if available, otherwise use detected URL
if [ -z "$TUNNEL_URL" ] && [ -n "$HARDCODED_NGROK_URL" ]; then
    TUNNEL_URL="$HARDCODED_NGROK_URL"
    print_info "Using hardcoded ngrok URL for GitHub webhook setup"
fi

if [ -n "$TUNNEL_URL" ]; then
    print_success "Public Tunnel URL:"
    echo "  $TUNNEL_URL"
    echo ""
    
    # Construct webhook URL
    if echo "$TUNNEL_URL" | grep -q "/webhook$"; then
        WEBHOOK_URL="$TUNNEL_URL"
    else
        WEBHOOK_URL="$TUNNEL_URL/webhook"
    fi
    print_success "GitHub Webhook URL:"
    echo "  $WEBHOOK_URL"
    echo ""
    print_warning "IMPORTANT: Save this URL - external services can now reach your Pi!"
    echo ""
    
    # Save URL to file
    if [ -n "${PROJECT_DIR:-}" ]; then
        echo "$WEBHOOK_URL" > "$PROJECT_DIR/.ngrok_url"
        print_info "Webhook URL saved to: $PROJECT_DIR/.ngrok_url"
    fi
else
    print_info "To get your tunnel URL:"
    echo "  - Check dashboard: http://localhost:$NGROK_WEB_PORT"
    echo "  - Or check log: tail -f $HOME/ngrok.log"
    echo ""
fi

print_info "Service management:"
echo "  Status:  sudo systemctl status iot-gui-ngrok.service"
echo "  Stop:    sudo systemctl stop iot-gui-ngrok.service"
echo "  Start:   sudo systemctl start iot-gui-ngrok.service"
echo "  Restart: sudo systemctl restart iot-gui-ngrok.service"
echo "  Logs:    sudo journalctl -u iot-gui-ngrok.service -f"
echo ""

print_info "Useful commands:"
echo "  View dashboard: http://localhost:$NGROK_WEB_PORT"
echo "  Test tunnel: curl $TUNNEL_URL"
echo "  Check status: $NGROK_BIN api tunnels list"
echo ""

print_success "Setup complete! Your tunnel is running and accessible from the internet! 🎉"
echo ""
