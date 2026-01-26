#!/bin/bash
# ============================================================================
# Get ngrok Public URL
# ============================================================================
# This script retrieves the current ngrok public URL
#
# Usage:
#   chmod +x get-ngrok-url.sh
#   ./get-ngrok-url.sh
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
NGROK_URL_FILE="$PROJECT_DIR/.ngrok_url"
SECRET_FILE="$PROJECT_DIR/.webhook_secret"

echo ""
echo "============================================================================"
echo "ngrok Webhook URL"
echo "============================================================================"
echo ""

# Check if ngrok is running
if ! pgrep -f "ngrok.*webhook" >/dev/null 2>&1; then
    print_warning "ngrok is not running"
    print_info "Start it with: sudo systemctl start iot-gui-ngrok.service"
    echo ""
fi

# Try to get URL from saved file
if [ -f "$NGROK_URL_FILE" ]; then
    SAVED_URL=$(cat "$NGROK_URL_FILE")
    print_info "Saved URL: $SAVED_URL"
    echo ""
fi

# Try to get URL from ngrok API
print_info "Getting current ngrok URL..."
NGROK_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -oP '"public_url":"https://[^"]*' | head -1 | cut -d'"' -f4)

if [ -n "$NGROK_URL" ]; then
    WEBHOOK_URL="$NGROK_URL/webhook"
    print_success "Current ngrok URL:"
    echo "  $WEBHOOK_URL"
    echo ""
    
    # Update saved file
    echo "$WEBHOOK_URL" > "$NGROK_URL_FILE"
    
    # Get webhook secret
    if [ -f "$SECRET_FILE" ]; then
        WEBHOOK_SECRET=$(cat "$SECRET_FILE")
        print_info "Webhook Secret: $WEBHOOK_SECRET"
    else
        print_warning "Webhook secret not found"
    fi
    
    echo ""
    print_info "GitHub Webhook Configuration:"
    echo "  URL: $WEBHOOK_URL"
    if [ -n "$WEBHOOK_SECRET" ]; then
        echo "  Secret: $WEBHOOK_SECRET"
    fi
    echo "  Content type: application/json"
    echo "  Events: Just the push event"
    echo ""
    print_info "GitHub Webhook Settings:"
    echo "  https://github.com/thienanlktl/Pideployment/settings/hooks"
    echo ""
else
    print_warning "Could not get ngrok URL"
    print_info "Check if ngrok is running:"
    echo "  sudo systemctl status iot-gui-ngrok.service"
    echo ""
    print_info "Or view ngrok dashboard:"
    echo "  http://localhost:4040"
    echo ""
    if [ -f "$NGROK_URL_FILE" ]; then
        print_info "Last known URL: $SAVED_URL"
    fi
fi

echo ""

