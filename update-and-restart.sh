#!/bin/bash
# ============================================================================
# AWS IoT Pub/Sub GUI - Update and Restart Script
# ============================================================================
# This script:
#   1. Pulls latest code from GitHub (main branch)
#   2. Updates Python dependencies if requirements.txt changed
#   3. Gracefully stops the running application
#   4. Restarts the application
#
# Usage:
#   ./update-and-restart.sh
#
# This script is typically called by the webhook listener or cron job
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

set -e  # Exit on error (we'll handle errors gracefully)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Get the script directory (project root)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration
VENV_DIR="$SCRIPT_DIR/venv"
APP_FILE="$SCRIPT_DIR/iot_pubsub_gui.py"
REQUIREMENTS_FILE="$SCRIPT_DIR/requirements.txt"
LOG_FILE="$SCRIPT_DIR/update.log"
PID_FILE="$SCRIPT_DIR/app.pid"
GIT_BRANCH="${GIT_BRANCH:-main}"

# Create log file if it doesn't exist
touch "$LOG_FILE"

# Function to log with timestamp
log_with_timestamp() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

print_step() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    log_with_timestamp "$1"
}

# Start logging
log_with_timestamp "=== Update and Restart Started ==="

print_step "Update and Restart Process Started"

# ============================================================================
# Step 1: Check if we're in a git repository
# ============================================================================
if [ ! -d ".git" ]; then
    print_error "Not a git repository. Please ensure you're in the project directory."
    log_with_timestamp "ERROR: Not a git repository"
    exit 1
fi

# ============================================================================
# Step 2: Check git remote configuration
# ============================================================================
print_info "Checking git remote configuration..."
GIT_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
if [ -z "$GIT_REMOTE" ]; then
    print_warning "No git remote 'origin' found. Skipping git pull."
    log_with_timestamp "WARNING: No git remote found"
else
    print_info "Git remote: $GIT_REMOTE"
fi

# ============================================================================
# Step 3: Pull latest code from GitHub
# ============================================================================
print_step "Step 1: Pulling Latest Code from GitHub"

if [ -n "$GIT_REMOTE" ]; then
    print_info "Fetching latest changes from origin/$GIT_BRANCH..."
    
    # Fetch latest changes
    if git fetch origin "$GIT_BRANCH" 2>&1 | tee -a "$LOG_FILE"; then
        print_success "Fetched latest changes"
    else
        print_error "Failed to fetch from git"
        log_with_timestamp "ERROR: git fetch failed"
        exit 1
    fi
    
    # Check if we're behind
    LOCAL_COMMIT=$(git rev-parse HEAD)
    REMOTE_COMMIT=$(git rev-parse "origin/$GIT_BRANCH" 2>/dev/null || echo "")
    
    if [ -n "$REMOTE_COMMIT" ] && [ "$LOCAL_COMMIT" != "$REMOTE_COMMIT" ]; then
        print_info "Local commit: $LOCAL_COMMIT"
        print_info "Remote commit: $REMOTE_COMMIT"
        print_info "Updates available. Pulling changes..."
        
        # Pull changes
        if git pull origin "$GIT_BRANCH" 2>&1 | tee -a "$LOG_FILE"; then
            print_success "Pulled latest code successfully"
            CODE_UPDATED=true
        else
            print_error "Failed to pull from git"
            log_with_timestamp "ERROR: git pull failed"
            exit 1
        fi
    else
        print_info "Already up to date with origin/$GIT_BRANCH"
        CODE_UPDATED=false
    fi
else
    print_warning "Skipping git pull (no remote configured)"
    CODE_UPDATED=false
fi

# ============================================================================
# Step 4: Check if virtual environment exists
# ============================================================================
print_step "Step 2: Checking Virtual Environment"

if [ ! -d "$VENV_DIR" ]; then
    print_warning "Virtual environment not found at: $VENV_DIR"
    print_info "Creating virtual environment..."
    
    if ! python3 -m venv "$VENV_DIR"; then
        print_error "Failed to create virtual environment"
        log_with_timestamp "ERROR: Failed to create venv"
        exit 1
    fi
    
    print_success "Virtual environment created"
    VENV_CREATED=true
else
    print_info "Virtual environment found at: $VENV_DIR"
    VENV_CREATED=false
fi

# Activate virtual environment
print_info "Activating virtual environment..."
source "$VENV_DIR/bin/activate" || {
    print_error "Failed to activate virtual environment"
    log_with_timestamp "ERROR: Failed to activate venv"
    exit 1
}

# ============================================================================
# Step 5: Update Python dependencies
# ============================================================================
print_step "Step 3: Updating Python Dependencies"

# Upgrade pip first
print_info "Upgrading pip..."
python -m pip install --upgrade --quiet pip setuptools wheel || {
    print_warning "Failed to upgrade pip, continuing anyway..."
}

# Check if requirements.txt exists
if [ -f "$REQUIREMENTS_FILE" ]; then
    print_info "Found requirements.txt, installing/updating dependencies..."
    
    # Install/upgrade dependencies
    if python -m pip install --upgrade -r "$REQUIREMENTS_FILE" 2>&1 | tee -a "$LOG_FILE"; then
        print_success "Dependencies updated from requirements.txt"
    else
        print_error "Failed to install some dependencies"
        print_warning "Continuing anyway..."
    fi
else
    print_info "No requirements.txt found, installing core dependencies..."
    
    # Install core dependencies if no requirements.txt
    python -m pip install --upgrade --quiet PyQt6 awsiotsdk awscrt cryptography python-dateutil || {
        print_warning "Some dependencies may have failed to install"
    }
    
    print_success "Core dependencies installed"
fi

# ============================================================================
# Step 6: Gracefully stop running application
# ============================================================================
print_step "Step 4: Stopping Running Application"

# Function to find and kill the application process
stop_application() {
    # Method 1: Check PID file
    if [ -f "$PID_FILE" ]; then
        OLD_PID=$(cat "$PID_FILE")
        if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
            print_info "Found process from PID file: $OLD_PID"
            print_info "Stopping process gracefully..."
            
            # Try graceful shutdown first (SIGTERM)
            kill -TERM "$OLD_PID" 2>/dev/null || true
            sleep 2
            
            # Check if still running
            if kill -0 "$OLD_PID" 2>/dev/null; then
                print_warning "Process still running, forcing shutdown..."
                kill -KILL "$OLD_PID" 2>/dev/null || true
                sleep 1
            fi
            
            print_success "Process stopped"
            rm -f "$PID_FILE"
            return 0
        else
            print_info "PID file exists but process not running, cleaning up..."
            rm -f "$PID_FILE"
        fi
    fi
    
    # Method 2: Find by process name
    print_info "Searching for running application processes..."
    
    # Find processes running iot_pubsub_gui.py
    PIDS=$(pgrep -f "iot_pubsub_gui.py" 2>/dev/null || true)
    
    if [ -n "$PIDS" ]; then
        for PID in $PIDS; do
            print_info "Found process: $PID"
            print_info "Stopping process gracefully..."
            
            # Try graceful shutdown
            kill -TERM "$PID" 2>/dev/null || true
            sleep 2
            
            # Check if still running
            if kill -0 "$PID" 2>/dev/null; then
                print_warning "Process $PID still running, forcing shutdown..."
                kill -KILL "$PID" 2>/dev/null || true
                sleep 1
            fi
            
            print_success "Process $PID stopped"
        done
        return 0
    else
        print_info "No running application processes found"
        return 1
    fi
}

# Stop the application
if stop_application; then
    print_success "Application stopped successfully"
    log_with_timestamp "Application stopped"
    sleep 1  # Brief pause before restart
else
    print_info "No application was running"
fi

# ============================================================================
# Step 7: Restart the application
# ============================================================================
print_step "Step 5: Restarting Application"

# Check if application file exists
if [ ! -f "$APP_FILE" ]; then
    print_error "Application file not found: $APP_FILE"
    log_with_timestamp "ERROR: Application file not found"
    exit 1
fi

print_info "Starting application: $APP_FILE"

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

# Use nohup to run in background and redirect output
nohup python "$APP_FILE" >> "$LOG_FILE" 2>&1 &
APP_PID=$!

# Save PID to file
echo "$APP_PID" > "$PID_FILE"

# Wait a moment to check if process started successfully
sleep 2

if kill -0 "$APP_PID" 2>/dev/null; then
    print_success "Application started successfully (PID: $APP_PID)"
    log_with_timestamp "Application started with PID: $APP_PID"
    print_info "Logs are being written to: $LOG_FILE"
else
    print_error "Application failed to start (PID: $APP_PID)"
    log_with_timestamp "ERROR: Application failed to start"
    rm -f "$PID_FILE"
    exit 1
fi

# ============================================================================
# Summary
# ============================================================================
print_step "Update and Restart Complete"

if [ "$CODE_UPDATED" = true ]; then
    print_success "Code updated and application restarted"
else
    print_success "Application restarted (no code changes)"
fi

print_info "Application PID: $APP_PID"
print_info "Log file: $LOG_FILE"
print_info "PID file: $PID_FILE"

log_with_timestamp "=== Update and Restart Completed Successfully ==="

exit 0

