#!/bin/bash
# ============================================================================
# Port Forwarding Setup Helper
# ============================================================================
# This script helps you set up port forwarding for GitHub webhooks
# It detects your network configuration and provides step-by-step instructions
#
# Usage:
#   chmod +x setup-port-forwarding.sh
#   ./setup-port-forwarding.sh
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

WEBHOOK_PORT=9000

echo ""
print_step "Port Forwarding Setup for GitHub Webhooks"

# ============================================================================
# Step 1: Detect Network Configuration
# ============================================================================
print_step "Step 1: Detecting Network Configuration"

# Get local IP
print_info "Detecting local IP address..."
LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')

if [ -z "$LOCAL_IP" ]; then
    LOCAL_IP=$(ip addr show 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | head -1)
fi

if [ -z "$LOCAL_IP" ]; then
    LOCAL_IP=$(ifconfig 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | head -1)
fi

if [ -n "$LOCAL_IP" ]; then
    print_success "Local IP address: $LOCAL_IP"
else
    print_error "Could not detect local IP address"
    exit 1
fi

# Get gateway (router IP)
print_info "Detecting router IP address..."
GATEWAY_IP=$(ip route | grep default | awk '{print $3}' | head -1)

if [ -n "$GATEWAY_IP" ]; then
    print_success "Router IP address: $GATEWAY_IP"
else
    print_warning "Could not detect router IP"
    GATEWAY_IP="192.168.1.1"
    print_info "Assuming router IP: $GATEWAY_IP (common default)"
fi

# Get public IP
print_info "Detecting public IP address..."
PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || curl -s --max-time 5 ipinfo.io/ip 2>/dev/null || echo "")

if [ -n "$PUBLIC_IP" ]; then
    print_success "Public IP address: $PUBLIC_IP"
else
    print_warning "Could not detect public IP (may be behind NAT)"
    PUBLIC_IP="YOUR_PUBLIC_IP"
fi

# Get MAC address
print_info "Detecting MAC address..."
MAC_ADDRESS=$(ip link show | grep -A 1 "state UP" | grep "link/ether" | awk '{print $2}' | head -1)

if [ -n "$MAC_ADDRESS" ]; then
    print_success "MAC address: $MAC_ADDRESS"
else
    print_warning "Could not detect MAC address"
    MAC_ADDRESS="YOUR_MAC_ADDRESS"
fi

# ============================================================================
# Step 2: Check if Port is Accessible
# ============================================================================
print_step "Step 2: Checking Port Accessibility"

# Check if webhook service is running
if systemctl is-active --quiet iot-gui-webhook.service 2>/dev/null; then
    print_success "Webhook service is running"
else
    print_warning "Webhook service is not running"
    print_info "Start it with: sudo systemctl start iot-gui-webhook.service"
fi

# Check if port is listening locally
if command -v netstat >/dev/null 2>&1; then
    if netstat -tuln 2>/dev/null | grep -q ":$WEBHOOK_PORT"; then
        print_success "Port $WEBHOOK_PORT is listening locally"
    else
        print_warning "Port $WEBHOOK_PORT is not listening"
    fi
elif command -v ss >/dev/null 2>&1; then
    if ss -tuln 2>/dev/null | grep -q ":$WEBHOOK_PORT"; then
        print_success "Port $WEBHOOK_PORT is listening locally"
    else
        print_warning "Port $WEBHOOK_PORT is not listening"
    fi
fi

# ============================================================================
# Step 3: Port Forwarding Instructions
# ============================================================================
print_step "Step 3: Port Forwarding Configuration"

echo ""
print_info "You need to configure port forwarding on your router."
echo ""
print_warning "IMPORTANT: Set a static IP for your Pi first!"
echo ""
print_info "Router Information:"
echo "  Router IP: $GATEWAY_IP"
echo "  Pi Local IP: $LOCAL_IP"
echo "  Pi MAC Address: $MAC_ADDRESS"
echo "  Port to Forward: $WEBHOOK_PORT"
echo ""

# Try to detect router brand
print_info "Attempting to detect router brand..."
ROUTER_BRAND=""
if command -v nmap >/dev/null 2>&1; then
    # Try to detect router type (basic check)
    print_info "Router detection requires manual identification"
fi

echo ""
print_info "Step-by-Step Router Configuration:"
echo ""
echo "1. Open router admin panel:"
echo "   http://$GATEWAY_IP"
echo "   (Common defaults: admin/admin or admin/password)"
echo ""
echo "2. Find 'Port Forwarding' or 'Virtual Server' section"
echo "   (May be under: Advanced → NAT → Port Forwarding)"
echo ""
echo "3. Add new port forwarding rule:"
echo "   - Service Name: GitHub Webhook (or any name)"
echo "   - External Port: $WEBHOOK_PORT"
echo "   - Internal IP: $LOCAL_IP"
echo "   - Internal Port: $WEBHOOK_PORT"
echo "   - Protocol: TCP"
echo "   - Enable: Yes"
echo ""
echo "4. Save and apply changes"
echo ""

# ============================================================================
# Step 4: Set Static IP (Important!)
# ============================================================================
print_step "Step 4: Setting Static IP (Required)"

echo ""
print_warning "CRITICAL: Your Pi must have a static IP for port forwarding to work!"
echo ""
echo "If your Pi IP changes, port forwarding will break."
echo ""

read -p "Does your Pi have a static IP? (y/n) " -n 1 -r
echo ""

case "$REPLY" in
    [Yy]*)
        print_success "Static IP is configured"
        ;;
    *)
        print_warning "You need to set a static IP!"
        echo ""
        echo "Option A: Set in Router (Recommended)"
        echo "  1. Log into router: http://$GATEWAY_IP"
        echo "  2. Find 'DHCP Reservation' or 'Static IP Assignment'"
        echo "  3. Reserve IP $LOCAL_IP for MAC: $MAC_ADDRESS"
        echo ""
        echo "Option B: Set on Pi"
        echo "  1. Edit: sudo nano /etc/dhcpcd.conf"
        echo "  2. Add at end:"
        echo "     interface eth0"
        echo "     static ip_address=$LOCAL_IP/24"
        echo "     static routers=$GATEWAY_IP"
        echo "  3. Reboot: sudo reboot"
        echo ""
        read -p "Press Enter after setting static IP..."
        ;;
esac

# ============================================================================
# Step 5: Test Port Forwarding
# ============================================================================
print_step "Step 5: Testing Port Forwarding"

echo ""
print_info "After configuring port forwarding on router, test it:"
echo ""

if [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "YOUR_PUBLIC_IP" ]; then
    print_info "Test from another device with internet:"
    echo "  curl http://$PUBLIC_IP:$WEBHOOK_PORT/health"
    echo ""
    print_info "Or use online port checker:"
    echo "  https://www.yougetsignal.com/tools/open-ports/"
    echo "  Enter: $PUBLIC_IP and port $WEBHOOK_PORT"
    echo ""
else
    print_info "Get your public IP first:"
    echo "  curl ifconfig.me"
    echo ""
    print_info "Then test from another device:"
    echo "  curl http://YOUR_PUBLIC_IP:$WEBHOOK_PORT/health"
    echo ""
fi

print_info "Expected response:"
echo '  {"status":"healthy","service":"iot-gui-webhook",...}'
echo ""

read -p "Have you configured port forwarding on router? (y/n) " -n 1 -r
echo ""

case "$REPLY" in
    [Yy]*)
        print_info "Testing local connectivity first..."
        if curl -s --max-time 5 http://localhost:$WEBHOOK_PORT/health >/dev/null 2>&1; then
            print_success "Local webhook is accessible"
        else
            print_warning "Local webhook not accessible - start service first"
        fi
        
        echo ""
        print_info "To test from internet, use:"
        echo "  curl http://$PUBLIC_IP:$WEBHOOK_PORT/health"
        echo ""
        print_info "Or ask someone to test it for you"
        ;;
    *)
        print_info "Configure port forwarding first, then test"
        ;;
esac

# ============================================================================
# Step 6: Webhook URL for GitHub
# ============================================================================
print_step "Step 6: GitHub Webhook URL"

echo ""
print_info "Use this URL in GitHub webhook configuration:"
echo ""

if [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "YOUR_PUBLIC_IP" ]; then
    WEBHOOK_URL="http://$PUBLIC_IP:$WEBHOOK_PORT/webhook"
    print_success "Webhook URL:"
    echo "  $WEBHOOK_URL"
    echo ""
    print_warning "Note: If your public IP changes, update webhook URL in GitHub"
else
    print_info "Get your public IP:"
    echo "  curl ifconfig.me"
    echo ""
    print_info "Then use:"
    echo "  http://YOUR_PUBLIC_IP:$WEBHOOK_PORT/webhook"
fi

echo ""
print_info "GitHub Webhook Setup:"
echo "  1. Go to: https://github.com/thienanlktl/Pideployment/settings/hooks"
echo "  2. Click 'Add webhook'"
echo "  3. Payload URL: $WEBHOOK_URL"
echo "  4. Secret: (from .webhook_secret file)"
echo "  5. Content type: application/json"
echo "  6. Events: Just the push event"
echo ""

# ============================================================================
# Summary
# ============================================================================
print_step "Port Forwarding Setup Summary"

echo ""
print_info "Configuration Summary:"
echo "  ✓ Pi Local IP: $LOCAL_IP"
echo "  ✓ Router IP: $GATEWAY_IP"
echo "  ✓ Public IP: $PUBLIC_IP"
echo "  ✓ Port: $WEBHOOK_PORT"
echo "  ✓ MAC Address: $MAC_ADDRESS"
echo ""
print_info "Next Steps:"
echo "  1. Set static IP for Pi (if not done)"
echo "  2. Configure port forwarding on router"
echo "  3. Test port forwarding"
echo "  4. Add webhook to GitHub with public IP"
echo ""
print_success "Port forwarding setup guide complete!"
echo ""

