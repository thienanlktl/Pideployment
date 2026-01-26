#!/bin/bash
# ============================================================================
# Setup Cron Fallback for Automated Updates
# ============================================================================
# This script sets up a cron job to periodically check for updates
# Use this if you can't set up a webhook (e.g., no public IP)
#
# Usage:
#   chmod +x setup-cron-fallback.sh
#   ./setup-cron-fallback.sh
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

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UPDATE_SCRIPT="$SCRIPT_DIR/update-and-restart.sh"
CRON_LOG="$SCRIPT_DIR/cron.log"

echo ""
echo "============================================================================"
echo "Cron Fallback Setup for Automated Updates"
echo "============================================================================"
echo ""

# Check if update script exists
if [ ! -f "$UPDATE_SCRIPT" ]; then
    print_error "Update script not found: $UPDATE_SCRIPT"
    exit 1
fi

# Make update script executable
chmod +x "$UPDATE_SCRIPT"
print_success "Update script is executable"

# Ask for update interval
echo ""
echo "How often should the system check for updates?"
echo "1. Every 5 minutes"
echo "2. Every 10 minutes"
echo "3. Every 15 minutes"
echo "4. Every 30 minutes"
echo "5. Every hour"
echo "6. Custom (enter cron expression)"
echo ""
read -p "Enter choice (1-6): " -n 1 -r
echo ""

case "$REPLY" in
    1)
        CRON_SCHEDULE="*/5 * * * *"
        INTERVAL="every 5 minutes"
        ;;
    2)
        CRON_SCHEDULE="*/10 * * * *"
        INTERVAL="every 10 minutes"
        ;;
    3)
        CRON_SCHEDULE="*/15 * * * *"
        INTERVAL="every 15 minutes"
        ;;
    4)
        CRON_SCHEDULE="*/30 * * * *"
        INTERVAL="every 30 minutes"
        ;;
    5)
        CRON_SCHEDULE="0 * * * *"
        INTERVAL="every hour"
        ;;
    6)
        echo ""
        echo "Enter cron expression (e.g., '*/10 * * * *' for every 10 minutes):"
        read -p "Cron schedule: " CRON_SCHEDULE
        INTERVAL="custom schedule: $CRON_SCHEDULE"
        ;;
    *)
        print_error "Invalid choice"
        exit 1
        ;;
esac

# Create cron job entry
CRON_ENTRY="$CRON_SCHEDULE $UPDATE_SCRIPT >> $CRON_LOG 2>&1"

print_info "Cron schedule: $INTERVAL"
print_info "Update script: $UPDATE_SCRIPT"
print_info "Log file: $CRON_LOG"
echo ""

# Check if cron entry already exists
if crontab -l 2>/dev/null | grep -q "$UPDATE_SCRIPT"; then
    print_warning "Cron entry for update script already exists"
    echo ""
    echo "Current crontab:"
    crontab -l | grep "$UPDATE_SCRIPT"
    echo ""
    read -p "Do you want to replace it? (y/n) " -n 1 -r
    echo ""
    
    case "$REPLY" in
        [Yy]*)
            # Remove existing entry
            crontab -l 2>/dev/null | grep -v "$UPDATE_SCRIPT" | crontab -
            print_info "Removed existing cron entry"
            ;;
        *)
            print_info "Keeping existing cron entry"
            exit 0
            ;;
    esac
fi

# Add cron entry
(crontab -l 2>/dev/null; echo "$CRON_ENTRY") | crontab -

if [ $? -eq 0 ]; then
    print_success "Cron job added successfully"
else
    print_error "Failed to add cron job"
    exit 1
fi

# Display current crontab
echo ""
print_info "Current crontab entries:"
crontab -l

echo ""
print_success "Cron fallback setup complete!"
echo ""
print_info "The system will check for updates $INTERVAL"
print_info "Logs will be written to: $CRON_LOG"
echo ""
print_info "To remove the cron job later, run:"
echo "  crontab -e"
echo "  (then delete the line with update-and-restart.sh)"
echo ""

