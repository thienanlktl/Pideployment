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

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$SCRIPT_DIR}"
NGROK_URL_FILE="$PROJECT_DIR/.ngrok_url"
SECRET_FILE="$PROJECT_DIR/.webhook_secret"

# Configuration
GITHUB_USER="${GITHUB_USER:-thienanlktl}"
REPO_NAME="${REPO_NAME:-Pideployment}"

# Hardcoded ngrok public URL for GitHub webhook setup
HARDCODED_NGROK_URL="https://tardy-vernita-howlingly.ngrok-free.dev"

echo ""
echo "============================================================================"
echo "ngrok Webhook URL"
echo "============================================================================"
echo ""

# ============================================================================
# Step 1: Check if ngrok is running
# ============================================================================
print_info "Step 1: Checking ngrok status..."

NGROK_RUNNING=false
NGROK_PROCESS_FOUND=false

# Check for ngrok processes (more flexible pattern)
if pgrep -f "ngrok" >/dev/null 2>&1; then
    NGROK_PROCESS_FOUND=true
    print_success "ngrok process found"
    
    # Show process info
    NGROK_PIDS=$(pgrep -f "ngrok" | tr '\n' ' ')
    print_info "ngrok PIDs: $NGROK_PIDS"
else
    print_warning "No ngrok process found"
fi

# Check systemd service status
if command -v systemctl >/dev/null 2>&1; then
    if systemctl list-units --type=service --all 2>/dev/null | grep -q "iot-gui-ngrok.service"; then
        print_info "Checking systemd service status..."
        if systemctl is-active --quiet iot-gui-ngrok.service 2>/dev/null; then
            print_success "ngrok systemd service is active"
            NGROK_RUNNING=true
        elif systemctl is-enabled --quiet iot-gui-ngrok.service 2>/dev/null; then
            print_warning "ngrok systemd service is enabled but not active"
            print_info "Start with: sudo systemctl start iot-gui-ngrok.service"
        else
            print_info "ngrok systemd service exists but is not enabled"
        fi
    else
        print_info "ngrok systemd service not found"
    fi
fi

if [ "$NGROK_PROCESS_FOUND" = true ] || [ "$NGROK_RUNNING" = true ]; then
    NGROK_RUNNING=true
fi

if [ "$NGROK_RUNNING" = false ] && [ "$NGROK_PROCESS_FOUND" = false ]; then
    print_warning "ngrok does not appear to be running"
    print_info "Start it with: sudo systemctl start iot-gui-ngrok.service"
    print_info "Or manually: ngrok start webhook"
    echo ""
fi

# ============================================================================
# Step 2: Try to get URL from saved file
# ============================================================================
print_info ""
print_info "Step 2: Checking saved URL..."

SAVED_URL=""
if [ -f "$NGROK_URL_FILE" ]; then
    SAVED_URL=$(cat "$NGROK_URL_FILE" 2>/dev/null | tr -d '\n\r ')
    if [ -n "$SAVED_URL" ]; then
        print_success "Found saved URL: $SAVED_URL"
    else
        print_warning "Saved URL file exists but is empty"
    fi
else
    print_info "No saved URL file found: $NGROK_URL_FILE"
fi

# ============================================================================
# Step 3: Try to get URL from ngrok API
# ============================================================================
print_info ""
print_info "Step 3: Getting current ngrok URL from API..."

NGROK_URL=""
NGROK_WEB_PORT=""
WEBHOOK_PORT="${WEBHOOK_PORT:-9000}"

# Try multiple ports to find ngrok API (4040 is default, others are fallbacks)
print_info "Checking ngrok API on multiple ports..."
for port in 4040 4041 4042 4043 4044; do
    if curl -s --max-time 2 "http://localhost:$port/api/tunnels" >/dev/null 2>&1; then
        NGROK_WEB_PORT="$port"
        print_success "Found ngrok API on port $port"
        break
    fi
done

if [ -z "$NGROK_WEB_PORT" ]; then
    print_warning "Could not find ngrok API on any port (4040-4044)"
    print_info "ngrok may not be running or web interface is disabled"
else
    print_info "Querying ngrok API on port $NGROK_WEB_PORT..."
    
    # Get tunnels JSON
    TUNNELS_JSON=$(curl -s --max-time 5 "http://localhost:$NGROK_WEB_PORT/api/tunnels" 2>/dev/null)
    
    if [ -z "$TUNNELS_JSON" ] || [ "$TUNNELS_JSON" = "{}" ]; then
        print_warning "ngrok API responded but no tunnels found"
    else
        # Extract tunnel URL (handle both old and new ngrok URL formats)
        NGROK_URL=$(echo "$TUNNELS_JSON" | grep -o '"public_url":"https://[^"]*' | head -1 | sed 's/"public_url":"//')
        
        # Also try alternative format
        if [ -z "$NGROK_URL" ]; then
            NGROK_URL=$(echo "$TUNNELS_JSON" | grep -oE 'https://[a-z0-9-]+\.ngrok-free\.dev' | head -1)
        fi
        if [ -z "$NGROK_URL" ]; then
            NGROK_URL=$(echo "$TUNNELS_JSON" | grep -oE 'https://[a-z0-9-]+\.ngrok\.io' | head -1)
        fi
        
        if [ -n "$NGROK_URL" ]; then
            print_success "Found ngrok tunnel URL: $NGROK_URL"
            
            # Verify tunnel is pointing to correct port
            TUNNEL_ADDR=$(echo "$TUNNELS_JSON" | grep -o "\"addr\":\"[^\"]*" | head -1 | sed 's/"addr":"//')
            if [ -n "$TUNNEL_ADDR" ]; then
                print_info "Tunnel address: $TUNNEL_ADDR"
                if echo "$TUNNEL_ADDR" | grep -q ":$WEBHOOK_PORT"; then
                    print_success "Tunnel is configured for webhook port $WEBHOOK_PORT"
                else
                    print_warning "Tunnel may not be configured for port $WEBHOOK_PORT"
                fi
            fi
        else
            print_warning "Could not extract URL from ngrok API response"
            print_info "API response preview:"
            echo "$TUNNELS_JSON" | head -5 | sed 's/^/  /'
        fi
    fi
fi

# ============================================================================
# Step 4: Construct webhook URL
# ============================================================================
print_info ""
print_info "Step 4: Constructing webhook URL..."

WEBHOOK_URL=""

if [ -n "$NGROK_URL" ]; then
    # Ensure webhook URL has /webhook suffix
    if echo "$NGROK_URL" | grep -q "/webhook$"; then
        WEBHOOK_URL="$NGROK_URL"
        print_info "URL already has /webhook suffix"
    else
        # Remove trailing slash if present
        NGROK_URL=$(echo "$NGROK_URL" | sed 's|/$||')
        WEBHOOK_URL="$NGROK_URL/webhook"
        print_info "Added /webhook suffix to URL"
    fi
    
    # Update saved file
    echo "$WEBHOOK_URL" > "$NGROK_URL_FILE"
    print_success "URL saved to: $NGROK_URL_FILE"
elif [ -n "$SAVED_URL" ]; then
    WEBHOOK_URL="$SAVED_URL"
    print_warning "Using saved URL (ngrok API not accessible)"
elif [ -n "$HARDCODED_NGROK_URL" ]; then
    # Use hardcoded URL as fallback
    print_info "Using hardcoded ngrok URL: $HARDCODED_NGROK_URL"
    if echo "$HARDCODED_NGROK_URL" | grep -q "/webhook$"; then
        WEBHOOK_URL="$HARDCODED_NGROK_URL"
    else
        WEBHOOK_URL="$HARDCODED_NGROK_URL/webhook"
    fi
    print_success "Using hardcoded webhook URL: $WEBHOOK_URL"
    echo "$WEBHOOK_URL" > "$NGROK_URL_FILE"
    print_success "URL saved to: $NGROK_URL_FILE"
else
    print_error "Could not determine webhook URL"
fi

# ============================================================================
# Step 5: Display results
# ============================================================================
echo ""
echo "============================================================================"
echo "Results"
echo "============================================================================"
echo ""

if [ -n "$WEBHOOK_URL" ]; then
    print_success "Webhook URL:"
    echo "  $WEBHOOK_URL"
    echo ""
    
    # Get webhook secret
    if [ -f "$SECRET_FILE" ]; then
        WEBHOOK_SECRET=$(cat "$SECRET_FILE" 2>/dev/null | tr -d '\n\r ')
        if [ -n "$WEBHOOK_SECRET" ]; then
            print_success "Webhook Secret:"
            echo "  $WEBHOOK_SECRET"
            echo ""
        else
            print_warning "Webhook secret file exists but is empty"
        fi
    else
        print_warning "Webhook secret file not found: $SECRET_FILE"
        print_info "Generate secret with: ./setup-deployment-from-scratch.sh"
    fi
    
    echo ""
    print_info "GitHub Webhook Configuration:"
    echo "  URL: $WEBHOOK_URL"
    if [ -n "$WEBHOOK_SECRET" ]; then
        echo "  Secret: $WEBHOOK_SECRET"
    fi
    echo "  Content type: application/json"
    echo "  Events: push"
    echo ""
    print_info "GitHub Webhook Settings:"
    echo "  https://github.com/$GITHUB_USER/$REPO_NAME/settings/hooks"
    echo ""
    
    # Test URL accessibility
    print_info "Testing webhook URL accessibility..."
    if curl -s --max-time 5 --head "$WEBHOOK_URL" >/dev/null 2>&1 || \
       curl -s --max-time 5 "$WEBHOOK_URL" >/dev/null 2>&1; then
        print_success "Webhook URL is accessible"
    else
        print_warning "Could not verify webhook URL accessibility"
        print_info "This is normal - webhook requires GitHub signature to respond"
    fi
else
    print_error "No webhook URL available"
    echo ""
    print_info "Troubleshooting steps:"
    echo "  1. Check if ngrok is running:"
    echo "     sudo systemctl status iot-gui-ngrok.service"
    echo "     ps aux | grep ngrok"
    echo ""
    echo "  2. Start ngrok if not running:"
    echo "     sudo systemctl start iot-gui-ngrok.service"
    echo "     OR"
    echo "     ngrok start webhook"
    echo ""
    echo "  3. Check ngrok dashboard:"
    if [ -n "$NGROK_WEB_PORT" ]; then
        echo "     http://localhost:$NGROK_WEB_PORT"
    else
        echo "     http://localhost:4040"
        echo "     http://localhost:4041"
    fi
    echo ""
    echo "  4. View ngrok logs:"
    echo "     sudo journalctl -u iot-gui-ngrok.service -f"
    echo "     OR"
    echo "     tail -f ~/ngrok.log"
    echo ""
    echo "  5. Re-run setup if needed:"
    echo "     ./setup-deployment-from-scratch.sh"
    echo ""
fi

echo ""
