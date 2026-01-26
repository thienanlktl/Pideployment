#!/bin/bash
# ============================================================================
# Get Webhook Information for GitHub Setup
# ============================================================================
# This script displays the current IP address and webhook secret
# Use this after Pi reboot to get updated webhook URL
#
# Usage:
#   chmod +x get-webhook-info.sh
#   ./get-webhook-info.sh
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

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$SCRIPT_DIR}"

# Configuration
GITHUB_USER="${GITHUB_USER:-thienanlktl}"
REPO_NAME="${REPO_NAME:-Pideployment}"
WEBHOOK_PORT="${WEBHOOK_PORT:-9000}"
SECRET_FILE="$PROJECT_DIR/.webhook_secret"

echo ""
echo "============================================================================"
echo "GitHub Webhook Information"
echo "============================================================================"
echo ""

# Check if ngrok is being used
NGROK_URL_FILE="$PROJECT_DIR/.ngrok_url"
if [ -f "$NGROK_URL_FILE" ] || pgrep -f "ngrok.*webhook" >/dev/null 2>&1; then
    print_info "ngrok is configured - using tunnel (no router config needed!)"
    echo ""
    if [ -f "$PROJECT_DIR/get-ngrok-url.sh" ]; then
        print_info "Getting ngrok URL..."
        chmod +x "$PROJECT_DIR/get-ngrok-url.sh" 2>/dev/null
        "$PROJECT_DIR/get-ngrok-url.sh"
        exit 0
    fi
fi

# Fallback to IP-based (if not using ngrok)
print_info "Using IP-based webhook (requires port forwarding)"
echo ""

# Get IP address
print_info "Detecting IP address..."
PI_IP=$(hostname -I 2>/dev/null | awk '{print $1}')

if [ -z "$PI_IP" ]; then
    PI_IP=$(ip addr show 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | head -1)
fi

if [ -z "$PI_IP" ]; then
    PI_IP=$(ifconfig 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | head -1)
fi

if [ -n "$PI_IP" ]; then
    print_success "Raspberry Pi IP address: $PI_IP"
else
    print_warning "Could not detect IP address"
    PI_IP="YOUR_PI_IP"
fi

# Get webhook secret
if [ -f "$SECRET_FILE" ]; then
    WEBHOOK_SECRET=$(cat "$SECRET_FILE")
    print_success "Webhook secret found"
else
    print_warning "Webhook secret file not found: $SECRET_FILE"
    print_info "Run setup-deployment-from-scratch.sh to generate secret"
    WEBHOOK_SECRET="NOT_FOUND"
fi

echo ""
echo "============================================================================"
echo "GitHub Webhook Configuration"
echo "============================================================================"
echo ""
echo "1. Go to GitHub Webhook Settings:"
echo "   https://github.com/$GITHUB_USER/$REPO_NAME/settings/hooks"
echo ""
echo "2. Click 'Add webhook' (or edit existing webhook)"
echo ""
echo "3. Fill in:"
echo ""
echo "   Payload URL:"
if [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "Unable to determine" ]; then
    echo "   http://$PUBLIC_IP:$WEBHOOK_PORT/webhook"
    echo ""
    print_warning "Note: Port forwarding must be configured on router!"
    print_info "Or use ngrok (no router config): ./setup-ngrok.sh"
else
    echo "   http://YOUR_PUBLIC_IP:$WEBHOOK_PORT/webhook"
    echo "   (Get public IP: curl ifconfig.me)"
    echo ""
    print_info "Or use ngrok (no router config): ./setup-ngrok.sh"
fi
echo ""
echo "   Content type:"
echo "   application/json"
echo ""
echo "   Secret:"
echo "   $WEBHOOK_SECRET"
echo ""
echo "   Which events:"
echo "   Just the push event"
echo ""
echo "   Active:"
echo "   ✓ Checked"
echo ""
echo "4. Click 'Add webhook' (or 'Update webhook')"
echo ""
echo "============================================================================"
echo ""

# Check if webhook service is running
if systemctl is-active --quiet iot-gui-webhook.service 2>/dev/null; then
    print_success "Webhook service is running"
else
    print_warning "Webhook service is not running"
    print_info "Start it with: sudo systemctl start iot-gui-webhook.service"
fi

# Check if port is listening
if command -v netstat >/dev/null 2>&1; then
    if netstat -tuln 2>/dev/null | grep -q ":$WEBHOOK_PORT"; then
        print_success "Port $WEBHOOK_PORT is listening"
    else
        print_warning "Port $WEBHOOK_PORT is not listening"
    fi
elif command -v ss >/dev/null 2>&1; then
    if ss -tuln 2>/dev/null | grep -q ":$WEBHOOK_PORT"; then
        print_success "Port $WEBHOOK_PORT is listening"
    else
        print_warning "Port $WEBHOOK_PORT is not listening"
    fi
fi

# Get public IP
print_info "Getting public IP address..."
PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo "Unable to determine")

if [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "Unable to determine" ]; then
    print_success "Public IP address: $PUBLIC_IP"
    echo ""
    echo "For webhook URL, use:"
    echo "  http://$PUBLIC_IP:$WEBHOOK_PORT/webhook"
    echo ""
    print_warning "Note: Public IP may change. Consider using Dynamic DNS (DuckDNS) for permanent solution."
else
    print_warning "Could not determine public IP"
    print_info "You may need to check your router's public IP manually"
fi

echo ""
print_info "Recommended: Use ngrok (no router config needed!)"
echo "  ./setup-ngrok.sh"
echo ""
print_warning "Alternative: Port Forwarding (requires router config)"
echo "  ./setup-port-forwarding.sh"
echo ""

