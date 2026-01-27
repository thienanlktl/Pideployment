#!/bin/bash
# ============================================================================
# AWS IoT Pub/Sub GUI - Update and Restart Script
# ============================================================================
# This script updates and restarts the UI application (iot_pubsub_gui.py):
#   1. Pulls latest code from GitHub (main branch)
#   2. Updates Python dependencies if requirements.txt changed
#   3. Gracefully stops the running iot_pubsub_gui.py application
#   4. Restarts iot_pubsub_gui.py with the latest code
#
# Usage:
#   ./update-and-restart.sh
#
# This script is typically called by:
#   - Webhook listener (when ngrok URL is accessed or GitHub webhook received)
#   - Cron job (if using cron fallback)
#   - Manual execution
#
# When called via webhook listener root endpoint:
#   https://tardy-vernita-howlingly.ngrok-free.dev/
#   This will trigger this script to update and restart the UI
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

set +e  # Don't exit on error immediately - we'll handle errors gracefully

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

# Function to log detailed process information
log_process_info() {
    local process_name="$1"
    local pid="$2"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        if command -v ps >/dev/null 2>&1; then
            local cmd=$(ps -p "$pid" -o command= 2>/dev/null || echo "unknown")
            local cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null || echo "unknown")
            local mem=$(ps -p "$pid" -o %mem= 2>/dev/null || echo "unknown")
            log_with_timestamp "PROCESS: $process_name (PID: $pid, CPU: $cpu%, MEM: $mem%, CMD: $cmd)"
        else
            log_with_timestamp "PROCESS: $process_name (PID: $pid, status: running)"
        fi
    else
        log_with_timestamp "PROCESS: $process_name (PID: $pid, status: not running)"
    fi
}

# Function to log file information
log_file_info() {
    local file_path="$1"
    if [ -f "$file_path" ]; then
        local size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null || echo "unknown")
        local mod_time=$(stat -f%Sm "$file_path" 2>/dev/null || stat -c%y "$file_path" 2>/dev/null || echo "unknown")
        log_with_timestamp "FILE: $file_path (Size: $size bytes, Modified: $mod_time)"
    else
        log_with_timestamp "FILE: $file_path (NOT FOUND)"
    fi
}

# Function to log git information
log_git_info() {
    local branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    local commit=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    local remote=$(git remote get-url origin 2>/dev/null || echo "none")
    log_with_timestamp "GIT: Branch=$branch, Commit=$commit, Remote=$remote"
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
log_with_timestamp "Updating UI application: iot_pubsub_gui.py"
log_with_timestamp "Script: $0"
log_with_timestamp "Working directory: $SCRIPT_DIR"
log_with_timestamp "User: $(whoami)"
log_with_timestamp "Hostname: $(hostname 2>/dev/null || echo 'unknown')"

# Log initial git state
log_git_info

# Log initial file states
log_file_info "$APP_FILE"
log_file_info "$REQUIREMENTS_FILE"
log_file_info "$PID_FILE"

# Log any existing processes
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$OLD_PID" ]; then
        log_process_info "Existing application (from PID file)" "$OLD_PID"
    fi
fi

# Find and log any running iot_pubsub_gui.py processes
EXISTING_PIDS=$(pgrep -f "iot_pubsub_gui.py" 2>/dev/null || true)
if [ -n "$EXISTING_PIDS" ]; then
    for pid in $EXISTING_PIDS; do
        log_process_info "Existing application (found by name)" "$pid"
    done
else
    log_with_timestamp "PROCESS: No existing iot_pubsub_gui.py processes found"
fi

print_step "Update and Restart Process Started - Updating UI Application (iot_pubsub_gui.py)"
print_info "This will pull latest code and restart the GUI application"

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
    log_with_timestamp "GIT_REMOTE: $GIT_REMOTE"
fi

# ============================================================================
# Step 3: Pull latest code from GitHub (main branch)
# ============================================================================
print_step "Step 1: Pulling Latest Code from Main Branch"

if [ -n "$GIT_REMOTE" ]; then
    # Ensure we're on the main branch
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
    log_with_timestamp "GIT: Current branch: $CURRENT_BRANCH, Target branch: $GIT_BRANCH"
    if [ -z "$CURRENT_BRANCH" ] || [ "$CURRENT_BRANCH" != "$GIT_BRANCH" ]; then
        print_info "Current branch: $CURRENT_BRANCH, switching to $GIT_BRANCH..."
        log_with_timestamp "GIT: Switching from $CURRENT_BRANCH to $GIT_BRANCH"
        if git checkout "$GIT_BRANCH" 2>&1 | tee -a "$LOG_FILE"; then
            print_success "Switched to $GIT_BRANCH branch"
            log_with_timestamp "GIT: Successfully switched to $GIT_BRANCH branch"
        else
            print_warning "Could not switch to $GIT_BRANCH, continuing with current branch..."
            log_with_timestamp "WARNING: Could not switch to $GIT_BRANCH branch"
        fi
    else
        print_info "Already on $GIT_BRANCH branch"
        log_with_timestamp "GIT: Already on $GIT_BRANCH branch"
    fi
    
    print_info "Fetching latest changes from origin/$GIT_BRANCH..."
    
    # Check if using SSH and set up SSH key if needed
    if echo "$GIT_REMOTE" | grep -q "^git@"; then
        SSH_KEY="$SCRIPT_DIR/id_ed25519_repo_pideployment"
        if [ -f "$SSH_KEY" ]; then
            print_info "Using SSH key for git operations: $SSH_KEY"
            log_with_timestamp "GIT: Using SSH key: $SSH_KEY"
            log_file_info "$SSH_KEY"
            export GIT_SSH_COMMAND="ssh -i $SSH_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"
        else
            log_with_timestamp "WARNING: SSH remote detected but SSH key not found: $SSH_KEY"
        fi
    else
        log_with_timestamp "GIT: Using HTTPS (no SSH key needed)"
    fi
    
    # Fetch latest changes
    log_with_timestamp "GIT: Starting fetch from origin/$GIT_BRANCH"
    if git fetch origin "$GIT_BRANCH" 2>&1 | tee -a "$LOG_FILE"; then
        print_success "Fetched latest changes"
        log_with_timestamp "GIT: Fetch completed successfully"
    else
        print_warning "Failed to fetch from git, trying without SSH key..."
        log_with_timestamp "WARNING: git fetch failed, retrying without SSH key"
        unset GIT_SSH_COMMAND
        if git fetch origin "$GIT_BRANCH" 2>&1 | tee -a "$LOG_FILE"; then
            print_success "Fetched latest changes (without SSH key)"
            log_with_timestamp "GIT: Fetch completed successfully (without SSH key)"
        else
            print_error "Failed to fetch from git"
            log_with_timestamp "ERROR: git fetch failed (both with and without SSH key)"
            exit 1
        fi
    fi
    
    # Always pull latest code from main (even if we think we're up to date)
    print_info "Pulling latest code from origin/$GIT_BRANCH..."
    
    # Check current state for logging
    LOCAL_COMMIT=$(git rev-parse HEAD)
    REMOTE_COMMIT=$(git rev-parse "origin/$GIT_BRANCH" 2>/dev/null || echo "")
    
    if [ -n "$REMOTE_COMMIT" ]; then
        print_info "Local commit: $LOCAL_COMMIT"
        print_info "Remote commit: $REMOTE_COMMIT"
        log_with_timestamp "GIT: Local commit: $LOCAL_COMMIT"
        log_with_timestamp "GIT: Remote commit: $REMOTE_COMMIT"
        if [ "$LOCAL_COMMIT" != "$REMOTE_COMMIT" ]; then
            log_with_timestamp "GIT: Commits differ - update available"
        else
            log_with_timestamp "GIT: Commits match - already up to date"
        fi
    fi
    
    # Pull changes (with SSH key if available)
    log_with_timestamp "GIT: Starting pull from origin/$GIT_BRANCH"
    if git pull origin "$GIT_BRANCH" 2>&1 | tee -a "$LOG_FILE"; then
        NEW_LOCAL_COMMIT=$(git rev-parse HEAD)
        log_with_timestamp "GIT: Pull completed, new commit: $NEW_LOCAL_COMMIT"
        if [ "$LOCAL_COMMIT" != "$NEW_LOCAL_COMMIT" ]; then
            print_success "Pulled latest code successfully (updated)"
            CODE_UPDATED=true
            log_with_timestamp "GIT: Code updated from $LOCAL_COMMIT to $NEW_LOCAL_COMMIT"
            
            # Log changed files
            CHANGED_FILES=$(git diff --name-only "$LOCAL_COMMIT" "$NEW_LOCAL_COMMIT" 2>/dev/null || echo "")
            if [ -n "$CHANGED_FILES" ]; then
                log_with_timestamp "GIT: Changed files: $CHANGED_FILES"
            fi
            
            # Verify iot_pubsub_gui.py was updated
            if [ -f "$APP_FILE" ]; then
                FILE_MODIFIED=$(git log -1 --format="%ct" -- "$APP_FILE" 2>/dev/null || echo "")
                if [ -n "$FILE_MODIFIED" ]; then
                    print_info "Verified: iot_pubsub_gui.py is at latest version (commit: $NEW_LOCAL_COMMIT)"
                    log_with_timestamp "FILE: iot_pubsub_gui.py verified at commit $NEW_LOCAL_COMMIT"
                    log_file_info "$APP_FILE"
                else
                    print_info "iot_pubsub_gui.py exists and will be used"
                    log_with_timestamp "FILE: iot_pubsub_gui.py exists (verification skipped)"
                fi
            fi
        else
            print_success "Pulled latest code successfully (already up to date)"
            CODE_UPDATED=false
            log_with_timestamp "GIT: Already up to date (no changes)"
        fi
    else
        print_warning "Failed to pull with current config, trying without SSH key..."
        log_with_timestamp "WARNING: git pull failed, retrying without SSH key"
        unset GIT_SSH_COMMAND
        if git pull origin "$GIT_BRANCH" 2>&1 | tee -a "$LOG_FILE"; then
            NEW_LOCAL_COMMIT=$(git rev-parse HEAD)
            log_with_timestamp "GIT: Pull completed (without SSH key), new commit: $NEW_LOCAL_COMMIT"
            if [ "$LOCAL_COMMIT" != "$NEW_LOCAL_COMMIT" ]; then
                print_success "Pulled latest code successfully (updated, without SSH key)"
                CODE_UPDATED=true
                log_with_timestamp "GIT: Code updated from $LOCAL_COMMIT to $NEW_LOCAL_COMMIT (without SSH key)"
                
                # Log changed files
                CHANGED_FILES=$(git diff --name-only "$LOCAL_COMMIT" "$NEW_LOCAL_COMMIT" 2>/dev/null || echo "")
                if [ -n "$CHANGED_FILES" ]; then
                    log_with_timestamp "GIT: Changed files: $CHANGED_FILES"
                fi
                
                # Verify iot_pubsub_gui.py was updated
                if [ -f "$APP_FILE" ]; then
                    FILE_MODIFIED=$(git log -1 --format="%ct" -- "$APP_FILE" 2>/dev/null || echo "")
                    if [ -n "$FILE_MODIFIED" ]; then
                        print_info "Verified: iot_pubsub_gui.py is at latest version (commit: $NEW_LOCAL_COMMIT)"
                        log_with_timestamp "FILE: iot_pubsub_gui.py verified at commit $NEW_LOCAL_COMMIT"
                        log_file_info "$APP_FILE"
                    else
                        print_info "iot_pubsub_gui.py exists and will be used"
                        log_with_timestamp "FILE: iot_pubsub_gui.py exists (verification skipped)"
                    fi
                fi
            else
                print_success "Pulled latest code successfully (already up to date, without SSH key)"
                CODE_UPDATED=false
                log_with_timestamp "GIT: Already up to date (no changes, without SSH key)"
            fi
        else
            print_error "Failed to pull from git"
            log_with_timestamp "ERROR: git pull failed (both with and without SSH key)"
            exit 1
        fi
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
log_with_timestamp "VENV: Activating virtual environment at $VENV_DIR"
source "$VENV_DIR/bin/activate" || {
    print_error "Failed to activate virtual environment"
    log_with_timestamp "ERROR: Failed to activate venv"
    exit 1
}
log_with_timestamp "VENV: Virtual environment activated"
log_with_timestamp "VENV: Python path: $(which python 2>/dev/null || echo 'unknown')"
log_with_timestamp "VENV: Python version: $(python --version 2>&1 || echo 'unknown')"

# ============================================================================
# Step 5: Update Python dependencies
# ============================================================================
print_step "Step 3: Updating Python Dependencies"

# Upgrade pip first
print_info "Upgrading pip..."
log_with_timestamp "PIP: Upgrading pip, setuptools, wheel"
python -m pip install --upgrade --quiet pip setuptools wheel || {
    print_warning "Failed to upgrade pip, continuing anyway..."
    log_with_timestamp "WARNING: Failed to upgrade pip"
}
log_with_timestamp "PIP: pip version: $(python -m pip --version 2>&1 || echo 'unknown')"

# Check if requirements.txt exists
if [ -f "$REQUIREMENTS_FILE" ]; then
    print_info "Found requirements.txt, installing/updating dependencies..."
    log_with_timestamp "PIP: Installing/updating dependencies from requirements.txt"
    log_file_info "$REQUIREMENTS_FILE"
    
    # Install/upgrade dependencies
    if python -m pip install --upgrade -r "$REQUIREMENTS_FILE" 2>&1 | tee -a "$LOG_FILE"; then
        print_success "Dependencies updated from requirements.txt"
        log_with_timestamp "PIP: Dependencies updated successfully"
    else
        print_error "Failed to install some dependencies"
        print_warning "Continuing anyway..."
        log_with_timestamp "WARNING: Some dependencies failed to install"
    fi
else
    print_info "No requirements.txt found, installing core dependencies..."
    log_with_timestamp "PIP: Installing core dependencies (no requirements.txt)"
    
    # Install core dependencies if no requirements.txt
    python -m pip install --upgrade --quiet PyQt6 awsiotsdk awscrt cryptography python-dateutil || {
        print_warning "Some dependencies may have failed to install"
        log_with_timestamp "WARNING: Some core dependencies may have failed"
    }
    
    print_success "Core dependencies installed"
    log_with_timestamp "PIP: Core dependencies installation completed"
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
        log_with_timestamp "STOP: Checking PID file, found PID: $OLD_PID"
        if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
            print_info "Found process from PID file: $OLD_PID"
            log_process_info "Application to stop (from PID file)" "$OLD_PID"
            print_info "Stopping process gracefully..."
            log_with_timestamp "STOP: Sending SIGTERM to PID $OLD_PID"
            
            # Try graceful shutdown first (SIGTERM)
            kill -TERM "$OLD_PID" 2>/dev/null || true
            sleep 2
            
            # Check if still running
            if kill -0 "$OLD_PID" 2>/dev/null; then
                print_warning "Process still running, forcing shutdown..."
                log_with_timestamp "STOP: Process still running, sending SIGKILL to PID $OLD_PID"
                kill -KILL "$OLD_PID" 2>/dev/null || true
                sleep 1
            else
                log_with_timestamp "STOP: Process stopped gracefully (SIGTERM)"
            fi
            
            print_success "Process stopped"
            log_with_timestamp "STOP: Process $OLD_PID stopped successfully"
            rm -f "$PID_FILE"
            log_with_timestamp "STOP: PID file removed"
            return 0
        else
            print_info "PID file exists but process not running, cleaning up..."
            log_with_timestamp "STOP: PID file exists but process $OLD_PID not running"
            rm -f "$PID_FILE"
            log_with_timestamp "STOP: PID file cleaned up"
        fi
    fi
    
    # Method 2: Find by process name
    print_info "Searching for running application processes..."
    log_with_timestamp "STOP: Searching for iot_pubsub_gui.py processes"
    
    # Find processes running iot_pubsub_gui.py
    PIDS=$(pgrep -f "iot_pubsub_gui.py" 2>/dev/null || true)
    
    if [ -n "$PIDS" ]; then
        log_with_timestamp "STOP: Found processes: $PIDS"
        for PID in $PIDS; do
            print_info "Found process: $PID"
            log_process_info "Application to stop (found by name)" "$PID"
            print_info "Stopping process gracefully..."
            log_with_timestamp "STOP: Sending SIGTERM to PID $PID"
            
            # Try graceful shutdown
            kill -TERM "$PID" 2>/dev/null || true
            sleep 2
            
            # Check if still running
            if kill -0 "$PID" 2>/dev/null; then
                print_warning "Process $PID still running, forcing shutdown..."
                log_with_timestamp "STOP: Process still running, sending SIGKILL to PID $PID"
                kill -KILL "$PID" 2>/dev/null || true
                sleep 1
            else
                log_with_timestamp "STOP: Process $PID stopped gracefully (SIGTERM)"
            fi
            
            print_success "Process $PID stopped"
            log_with_timestamp "STOP: Process $PID stopped successfully"
        done
        return 0
    else
        print_info "No running application processes found"
        log_with_timestamp "STOP: No running application processes found"
        return 1
    fi
}

# Stop the application
log_with_timestamp "STOP: Starting application stop process"
if stop_application; then
    print_success "Application stopped successfully"
    log_with_timestamp "STOP: Application stopped successfully"
    sleep 1  # Brief pause before restart
    log_with_timestamp "STOP: Waiting 1 second before restart"
else
    print_info "No application was running"
    log_with_timestamp "STOP: No application was running (nothing to stop)"
fi

# ============================================================================
# Step 7: Pre-startup Environment and System Checks
# ============================================================================
print_step "Step 5: Pre-Startup System Checks"

# Function to check and fix permissions
check_and_fix_permissions() {
    print_info "Checking file and directory permissions..."
    
    # Check script directory permissions
    if [ ! -r "$SCRIPT_DIR" ] || [ ! -w "$SCRIPT_DIR" ] || [ ! -x "$SCRIPT_DIR" ]; then
        print_warning "Script directory has permission issues: $SCRIPT_DIR"
        log_with_timestamp "WARNING: Script directory permission issues"
    fi
    
    # Check application file permissions
    if [ -f "$APP_FILE" ]; then
        if [ ! -r "$APP_FILE" ]; then
            print_warning "Application file is not readable, attempting to fix..."
            chmod +r "$APP_FILE" 2>/dev/null || {
                print_error "Failed to fix application file read permissions"
                log_with_timestamp "ERROR: Cannot fix application file permissions"
            }
        fi
    fi
    
    # Check venv permissions
    if [ -d "$VENV_DIR" ]; then
        if [ ! -r "$VENV_DIR" ] || [ ! -x "$VENV_DIR" ]; then
            print_warning "Venv directory has permission issues, attempting to fix..."
            chmod -R u+rX "$VENV_DIR" 2>/dev/null || {
                print_warning "Could not fix all venv permissions (may need sudo)"
                log_with_timestamp "WARNING: Venv permission issues may persist"
            }
        fi
    fi
    
    # Check log directory permissions
    LOG_DIR="$SCRIPT_DIR/logs"
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR" 2>/dev/null || {
            print_error "Failed to create log directory: $LOG_DIR"
            log_with_timestamp "ERROR: Cannot create log directory"
            return 1
        }
    fi
    
    if [ ! -w "$LOG_DIR" ]; then
        print_warning "Log directory is not writable, attempting to fix..."
        chmod u+w "$LOG_DIR" 2>/dev/null || {
            print_error "Failed to fix log directory write permissions"
            log_with_timestamp "ERROR: Cannot write to log directory"
            return 1
        }
    fi
    
    # Check PID file location permissions
    PID_DIR=$(dirname "$PID_FILE")
    if [ "$PID_DIR" != "." ] && [ ! -w "$PID_DIR" ]; then
        print_warning "PID file directory is not writable, attempting to fix..."
        chmod u+w "$PID_DIR" 2>/dev/null || {
            print_warning "Could not fix PID directory permissions"
        }
    fi
    
    print_success "Permission checks completed"
    log_with_timestamp "PERMISSIONS: Permission checks completed"
    return 0
}

# Function to check system resources
check_system_resources() {
    print_info "Checking system resources..."
    
    # Check disk space (need at least 100MB free)
    if command -v df >/dev/null 2>&1; then
        AVAILABLE_SPACE=$(df "$SCRIPT_DIR" | tail -1 | awk '{print $4}' 2>/dev/null || echo "0")
        if [ -n "$AVAILABLE_SPACE" ] && [ "$AVAILABLE_SPACE" -lt 102400 ]; then
            print_warning "Low disk space: ${AVAILABLE_SPACE}KB available (recommended: >100MB)"
            log_with_timestamp "WARNING: Low disk space: ${AVAILABLE_SPACE}KB"
        else
            print_info "Disk space OK: ${AVAILABLE_SPACE}KB available"
            log_with_timestamp "RESOURCES: Disk space: ${AVAILABLE_SPACE}KB"
        fi
    fi
    
    # Check memory (if available)
    if command -v free >/dev/null 2>&1; then
        MEM_INFO=$(free -m 2>/dev/null | grep Mem || echo "")
        if [ -n "$MEM_INFO" ]; then
            MEM_AVAILABLE=$(echo "$MEM_INFO" | awk '{print $7}')
            if [ -n "$MEM_AVAILABLE" ] && [ "$MEM_AVAILABLE" -lt 100 ]; then
                print_warning "Low available memory: ${MEM_AVAILABLE}MB (recommended: >100MB)"
                log_with_timestamp "WARNING: Low memory: ${MEM_AVAILABLE}MB"
            else
                print_info "Memory OK: ${MEM_AVAILABLE}MB available"
                log_with_timestamp "RESOURCES: Memory: ${MEM_AVAILABLE}MB"
            fi
        fi
    fi
    
    return 0
}

# Function to validate environment
validate_environment() {
    print_info "Validating environment..."
    
    # Check critical environment variables
    MISSING_ENV=0
    
    # Check if we can determine user
    if [ -z "$USER" ] && [ -z "$SUDO_USER" ]; then
        USER=$(whoami 2>/dev/null || echo "unknown")
        export USER
        print_info "Set USER=$USER"
    fi
    
    # Check if we can determine home directory
    if [ -z "$HOME" ]; then
        HOME=$(eval echo ~$USER 2>/dev/null || echo "/tmp")
        export HOME
        print_info "Set HOME=$HOME"
    fi
    
    # Verify home directory exists and is accessible
    if [ ! -d "$HOME" ] || [ ! -r "$HOME" ]; then
        print_warning "Home directory issue: $HOME"
        log_with_timestamp "WARNING: Home directory may not be accessible"
        MISSING_ENV=$((MISSING_ENV + 1))
    fi
    
    # Check DISPLAY for GUI
    if [ -z "$DISPLAY" ]; then
        # Try to detect and set DISPLAY
        if [ -n "$XDG_SESSION_ID" ] || [ -n "$WAYLAND_DISPLAY" ]; then
            export DISPLAY=:0 2>/dev/null || true
            print_info "Set DISPLAY=:0 for GUI"
        elif [ -S "/tmp/.X11-unix/X0" ] 2>/dev/null; then
            export DISPLAY=:0
            print_info "Detected X server, set DISPLAY=:0"
        else
            print_warning "DISPLAY not set - GUI may not work"
            log_with_timestamp "WARNING: DISPLAY not set"
        fi
    fi
    
    # Check PATH
    if [ -z "$PATH" ]; then
        export PATH="/usr/local/bin:/usr/bin:/bin"
        print_warning "PATH was empty, set default PATH"
        log_with_timestamp "WARNING: PATH was empty"
    fi
    
    # Verify Python is in PATH or use venv Python
    if ! command -v python3 >/dev/null 2>&1 && ! command -v python >/dev/null 2>&1; then
        if [ -f "$VENV_DIR/bin/python" ]; then
            print_info "System Python not found, will use venv Python"
        else
            print_error "No Python found in PATH or venv"
            log_with_timestamp "ERROR: No Python available"
            return 1
        fi
    fi
    
    if [ "$MISSING_ENV" -eq 0 ]; then
        print_success "Environment validation passed"
        log_with_timestamp "ENV: Environment validation passed"
    else
        print_warning "Environment validation completed with $MISSING_ENV warning(s)"
        log_with_timestamp "ENV: Environment validation completed with warnings"
    fi
    
    return 0
}

# Function to check network connectivity (for AWS IoT)
check_network_connectivity() {
    print_info "Checking network connectivity..."
    
    # Check if we can resolve DNS
    if command -v nslookup >/dev/null 2>&1 || command -v host >/dev/null 2>&1; then
        if command -v nslookup >/dev/null 2>&1; then
            if nslookup -timeout=2 google.com >/dev/null 2>&1; then
                print_info "Network connectivity OK (DNS working)"
                log_with_timestamp "NETWORK: DNS connectivity OK"
                return 0
            fi
        elif command -v host >/dev/null 2>&1; then
            if host -W 2 google.com >/dev/null 2>&1; then
                print_info "Network connectivity OK (DNS working)"
                log_with_timestamp "NETWORK: DNS connectivity OK"
                return 0
            fi
        fi
    fi
    
    # Try ping as fallback
    if command -v ping >/dev/null 2>&1; then
        if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
            print_info "Network connectivity OK (ping working)"
            log_with_timestamp "NETWORK: Ping connectivity OK"
            return 0
        fi
    fi
    
    print_warning "Network connectivity check failed (may still work for local resources)"
    log_with_timestamp "WARNING: Network connectivity check failed"
    return 0  # Don't fail on network check
}

# Function to verify file system integrity
check_filesystem() {
    print_info "Checking file system integrity..."
    
    # Check if script directory is accessible
    if [ ! -d "$SCRIPT_DIR" ]; then
        print_error "Script directory does not exist: $SCRIPT_DIR"
        log_with_timestamp "ERROR: Script directory missing"
        return 1
    fi
    
    # Check if we can write to script directory
    if [ ! -w "$SCRIPT_DIR" ]; then
        print_error "Cannot write to script directory: $SCRIPT_DIR"
        log_with_timestamp "ERROR: Script directory not writable"
        return 1
    fi
    
    # Check if application file exists and is readable
    if [ ! -f "$APP_FILE" ]; then
        print_error "Application file not found: $APP_FILE"
        log_with_timestamp "ERROR: Application file not found"
        return 1
    fi
    
    if [ ! -r "$APP_FILE" ]; then
        print_error "Application file is not readable: $APP_FILE"
        log_with_timestamp "ERROR: Application file not readable"
        return 1
    fi
    
    print_success "File system checks passed"
    log_with_timestamp "FILESYSTEM: File system checks passed"
    return 0
}

# Run all pre-startup checks
print_info "Running comprehensive pre-startup checks..."

# Check file system first (critical)
if ! check_filesystem; then
    print_error "File system checks failed - cannot proceed"
    log_with_timestamp "ERROR: File system checks failed"
    exit 1
fi

# Check and fix permissions
if ! check_and_fix_permissions; then
    print_error "Permission checks failed - cannot proceed"
    log_with_timestamp "ERROR: Permission checks failed"
    exit 1
fi

# Validate environment
if ! validate_environment; then
    print_error "Environment validation failed - cannot proceed"
    log_with_timestamp "ERROR: Environment validation failed"
    exit 1
fi

# Check system resources (warnings only)
check_system_resources

# Check network (warnings only)
check_network_connectivity

print_success "All pre-startup checks completed"
log_with_timestamp "PRE-STARTUP: All checks completed"

# ============================================================================
# Step 8: Restart the application
# ============================================================================
print_step "Step 6: Restarting Application"

# Check if application file exists (redundant but safe)
if [ ! -f "$APP_FILE" ]; then
    print_error "Application file not found: $APP_FILE"
    log_with_timestamp "ERROR: Application file not found"
    exit 1
fi

# Verify we have the latest version of iot_pubsub_gui.py
print_info "Verifying application file is up to date..."
if [ -n "$NEW_LOCAL_COMMIT" ]; then
    # Check if file is at the latest commit
    FILE_IN_HEAD=$(git ls-tree -r HEAD --name-only | grep -q "^iot_pubsub_gui.py$" && echo "yes" || echo "no")
    if [ "$FILE_IN_HEAD" = "yes" ]; then
        print_success "Verified: iot_pubsub_gui.py is at latest commit ($NEW_LOCAL_COMMIT)"
        log_with_timestamp "Verified: iot_pubsub_gui.py is at latest commit"
    else
        print_warning "iot_pubsub_gui.py may not be in latest commit, but file exists"
    fi
else
    # Get current commit if NEW_LOCAL_COMMIT not set
    CURRENT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "")
    if [ -n "$CURRENT_COMMIT" ]; then
        print_info "Using iot_pubsub_gui.py from commit: $CURRENT_COMMIT"
    fi
fi

# Get file info for logging
FILE_SIZE=$(stat -f%z "$APP_FILE" 2>/dev/null || stat -c%s "$APP_FILE" 2>/dev/null || echo "unknown")
FILE_MOD_TIME=$(stat -f%Sm "$APP_FILE" 2>/dev/null || stat -c%y "$APP_FILE" 2>/dev/null || echo "unknown")
print_info "Application file: $APP_FILE (Size: $FILE_SIZE bytes, Modified: $FILE_MOD_TIME)"

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

# Ensure we're using Python from venv
if [ -z "$VIRTUAL_ENV" ] || [ "$VIRTUAL_ENV" != "$VENV_DIR" ]; then
    source "$VENV_DIR/bin/activate"
fi

# Use Python from venv (explicit path for reliability)
VENV_PYTHON="$VENV_DIR/bin/python"
if [ ! -f "$VENV_PYTHON" ]; then
    print_error "Python not found in virtual environment: $VENV_PYTHON"
    log_with_timestamp "ERROR: Python not found in venv"
    exit 1
fi

# Verify venv Python is working
print_info "Verifying virtual environment Python..."
if ! "$VENV_PYTHON" --version >/dev/null 2>&1; then
    print_error "Virtual environment Python is not working"
    log_with_timestamp "ERROR: venv Python failed version check"
    exit 1
fi

# Verify critical packages are available in venv
print_info "Verifying required packages in virtual environment..."
if ! "$VENV_PYTHON" -c "import PyQt6; import awsiot" 2>/dev/null; then
    print_warning "Some required packages may be missing in venv"
    log_with_timestamp "WARNING: Package verification failed - may cause issues"
    # Try to show what's missing
    "$VENV_PYTHON" -c "import PyQt6" 2>&1 | head -1 >> "$LOG_FILE" || true
    "$VENV_PYTHON" -c "import awsiot" 2>&1 | head -1 >> "$LOG_FILE" || true
else
    print_success "Required packages verified in virtual environment"
    log_with_timestamp "START: Required packages verified"
fi

# Create logs directory if needed
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

# Create a wrapper script to ensure venv is properly activated
WRAPPER_SCRIPT="$SCRIPT_DIR/.run_app_wrapper.sh"
cat > "$WRAPPER_SCRIPT" << WRAPPER_EOF
#!/bin/bash
# Wrapper script to run application with proper venv activation
SCRIPT_DIR_WRAPPER="$(cd "$(dirname "\$0")" && pwd)"
VENV_DIR_WRAPPER="\$SCRIPT_DIR_WRAPPER/venv"
APP_FILE_WRAPPER="\$SCRIPT_DIR_WRAPPER/iot_pubsub_gui.py"

# Preserve important environment variables from parent
if [ -n "\$DISPLAY" ]; then
    export DISPLAY="\$DISPLAY"
fi
if [ -n "\$HOME" ]; then
    export HOME="\$HOME"
fi
if [ -n "\$USER" ]; then
    export USER="\$USER"
fi
if [ -n "\$XDG_RUNTIME_DIR" ]; then
    export XDG_RUNTIME_DIR="\$XDG_RUNTIME_DIR"
fi
if [ -n "\$XDG_SESSION_ID" ]; then
    export XDG_SESSION_ID="\$XDG_SESSION_ID"
fi

# Activate virtual environment
source "\$VENV_DIR_WRAPPER/bin/activate" || {
    echo "ERROR: Failed to activate virtual environment" >&2
    exit 1
}

# Verify Python is from venv
if ! command -v python >/dev/null 2>&1; then
    echo "ERROR: Python not found in PATH after venv activation" >&2
    exit 1
fi

# Verify we're using venv Python
PYTHON_PATH=\$(which python)
if [[ "\$PYTHON_PATH" != "\$VENV_DIR_WRAPPER"* ]]; then
    echo "ERROR: Not using venv Python. Got: \$PYTHON_PATH" >&2
    exit 1
fi

# Verify critical packages are available
if ! python -c "import PyQt6; import awsiot" 2>/dev/null; then
    echo "ERROR: Required packages (PyQt6, awsiot) not found in venv" >&2
    python -c "import PyQt6" 2>&1 | head -1 >&2
    python -c "import awsiot" 2>&1 | head -1 >&2
    exit 1
fi

# Run the application
cd "\$SCRIPT_DIR_WRAPPER"
exec python "\$APP_FILE_WRAPPER"
WRAPPER_EOF

chmod +x "$WRAPPER_SCRIPT"
log_with_timestamp "START: Created wrapper script: $WRAPPER_SCRIPT"

# Use nohup to run in background and redirect output
# Use wrapper script to ensure venv is properly activated
log_with_timestamp "START: Launching application with wrapper script"
log_with_timestamp "START: Output will be logged to: $LOG_DIR/app.log"
log_with_timestamp "START: DISPLAY=$DISPLAY"
log_with_timestamp "START: VIRTUAL_ENV=$VENV_DIR"
log_with_timestamp "START: VENV_PYTHON=$VENV_PYTHON"
log_with_timestamp "START: Wrapper script: $WRAPPER_SCRIPT"

# Clear any old log entries to start fresh
if [ -f "$LOG_DIR/app.log" ]; then
    log_with_timestamp "START: Clearing old app.log (backing up to app.log.old)"
    mv "$LOG_DIR/app.log" "$LOG_DIR/app.log.old" 2>/dev/null || true
fi

# Start the application with proper environment
# Use setsid to detach from terminal and prevent SIGHUP
# Use wrapper script to ensure venv is properly activated
# Pass DISPLAY explicitly to the wrapper
log_with_timestamp "START: Starting application with setsid and nohup via wrapper script"
if [ -n "$DISPLAY" ]; then
    DISPLAY="$DISPLAY" setsid nohup "$WRAPPER_SCRIPT" >> "$LOG_DIR/app.log" 2>&1 &
else
    setsid nohup "$WRAPPER_SCRIPT" >> "$LOG_DIR/app.log" 2>&1 &
fi
APP_PID=$!

log_with_timestamp "START: Application launched, PID: $APP_PID"

# Save PID to file
echo "$APP_PID" > "$PID_FILE"
log_with_timestamp "START: PID saved to $PID_FILE"

# Function to check if app is still running and log details
check_app_status() {
    local pid=$1
    local check_name=$2
    if kill -0 "$pid" 2>/dev/null; then
        log_with_timestamp "STATUS ($check_name): Process $pid is running"
        if command -v ps >/dev/null 2>&1; then
            local cmd=$(ps -p "$pid" -o command= 2>/dev/null || echo "unknown")
            local cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | xargs || echo "unknown")
            local mem=$(ps -p "$pid" -o %mem= 2>/dev/null | xargs || echo "unknown")
            local state=$(ps -p "$pid" -o state= 2>/dev/null | xargs || echo "unknown")
            log_with_timestamp "STATUS ($check_name): PID=$pid, CPU=${cpu}%, MEM=${mem}%, STATE=$state, CMD=$cmd"
        fi
        return 0
    else
        log_with_timestamp "STATUS ($check_name): Process $pid is NOT running"
        return 1
    fi
}

# Function to check app.log for errors
check_app_logs() {
    if [ -f "$LOG_DIR/app.log" ]; then
        local error_count=$(grep -i "error\|exception\|traceback\|fatal\|import.*error\|module.*not.*found\|cannot.*import" "$LOG_DIR/app.log" 2>/dev/null | wc -l || echo "0")
        if [ "$error_count" -gt 0 ]; then
            log_with_timestamp "WARNING: Found $error_count potential errors in app.log"
            log_with_timestamp "ERROR: Last 30 lines of app.log with errors:"
            grep -i "error\|exception\|traceback\|fatal\|import.*error\|module.*not.*found\|cannot.*import" "$LOG_DIR/app.log" 2>/dev/null | tail -10 >> "$LOG_FILE" || true
            return 1  # Return error status
        fi
        log_with_timestamp "STATUS: Last 5 lines of app.log:"
        tail -5 "$LOG_DIR/app.log" >> "$LOG_FILE" 2>/dev/null || true
        return 0  # No errors found
    else
        log_with_timestamp "WARNING: app.log file not found yet"
        return 0  # File doesn't exist yet, not an error
    fi
}

# Function to attempt recovery if app fails
attempt_recovery() {
    local failed_pid=$1
    print_info "Attempting recovery procedures..."
    log_with_timestamp "RECOVERY: Starting recovery procedures"
    
    # Check for common issues and try to fix them
    
    # 1. Check if it's a permission issue
    if [ -f "$LOG_DIR/app.log" ]; then
        if grep -qi "permission.*denied\|cannot.*open.*file\|access.*denied" "$LOG_DIR/app.log" 2>/dev/null; then
            print_warning "Permission errors detected - attempting to fix..."
            log_with_timestamp "RECOVERY: Permission errors detected"
            
            # Try to fix permissions
            if [ -f "$APP_FILE" ]; then
                chmod +r "$APP_FILE" 2>/dev/null || true
            fi
            if [ -d "$VENV_DIR" ]; then
                chmod -R u+rX "$VENV_DIR/bin" 2>/dev/null || true
            fi
            if [ -d "$LOG_DIR" ]; then
                chmod u+w "$LOG_DIR" 2>/dev/null || true
            fi
            
            print_info "Permissions adjusted - may need manual intervention"
            log_with_timestamp "RECOVERY: Permissions adjusted"
        fi
    fi
    
    # 2. Check if it's an environment issue
    if [ -f "$LOG_DIR/app.log" ]; then
        if grep -qi "cannot.*connect.*to.*x.*server\|no.*display\|qt.*platform" "$LOG_DIR/app.log" 2>/dev/null; then
            print_warning "Display/GUI errors detected"
            log_with_timestamp "RECOVERY: Display/GUI errors detected"
            print_info "Try setting DISPLAY manually: export DISPLAY=:0"
        fi
    fi
    
    # 3. Check if it's a venv issue
    if [ -f "$LOG_DIR/app.log" ]; then
        if grep -qi "no.*module.*named\|cannot.*import" "$LOG_DIR/app.log" 2>/dev/null; then
            print_warning "Missing packages detected - may need to reinstall dependencies"
            log_with_timestamp "RECOVERY: Missing packages detected"
            print_info "Try running: source venv/bin/activate && pip install -r requirements.txt"
        fi
    fi
    
    # 4. Check if it's a resource issue
    if command -v df >/dev/null 2>&1; then
        AVAILABLE_SPACE=$(df "$SCRIPT_DIR" | tail -1 | awk '{print $4}' 2>/dev/null || echo "0")
        if [ -n "$AVAILABLE_SPACE" ] && [ "$AVAILABLE_SPACE" -lt 51200 ]; then
            print_error "Critical: Very low disk space: ${AVAILABLE_SPACE}KB"
            log_with_timestamp "RECOVERY: Critical low disk space"
            print_info "Free up disk space and try again"
        fi
    fi
    
    # 5. Log recovery summary
    log_with_timestamp "RECOVERY: Recovery procedures completed"
    print_info "Recovery procedures completed - check logs for details"
    
    # Provide helpful error summary
    echo ""
    print_error "Application failed to start. Common solutions:"
    echo "  1. Check application logs: $LOG_DIR/app.log"
    echo "  2. Verify permissions: chmod +r $APP_FILE"
    echo "  3. Verify venv: source venv/bin/activate && pip install -r requirements.txt"
    echo "  4. Check DISPLAY: export DISPLAY=:0"
    echo "  5. Check disk space: df -h"
    echo "  6. Try manual run: ./run-application-manual.sh"
    echo ""
}

# Function to attempt recovery if app fails
attempt_recovery() {
    local failed_pid=$1
    print_info "Attempting recovery procedures..."
    log_with_timestamp "RECOVERY: Starting recovery procedures"
    
    # Check for common issues and try to fix them
    
    # 1. Check if it's a permission issue
    if [ -f "$LOG_DIR/app.log" ]; then
        if grep -qi "permission.*denied\|cannot.*open.*file\|access.*denied" "$LOG_DIR/app.log" 2>/dev/null; then
            print_warning "Permission errors detected - attempting to fix..."
            log_with_timestamp "RECOVERY: Permission errors detected"
            
            # Try to fix permissions
            if [ -f "$APP_FILE" ]; then
                chmod +r "$APP_FILE" 2>/dev/null || true
            fi
            if [ -d "$VENV_DIR" ]; then
                chmod -R u+rX "$VENV_DIR/bin" 2>/dev/null || true
            fi
            if [ -d "$LOG_DIR" ]; then
                chmod u+w "$LOG_DIR" 2>/dev/null || true
            fi
            
            print_info "Permissions adjusted - may need manual intervention"
            log_with_timestamp "RECOVERY: Permissions adjusted"
        fi
    fi
    
    # 2. Check if it's an environment issue
    if [ -f "$LOG_DIR/app.log" ]; then
        if grep -qi "cannot.*connect.*to.*x.*server\|no.*display\|qt.*platform" "$LOG_DIR/app.log" 2>/dev/null; then
            print_warning "Display/GUI errors detected"
            log_with_timestamp "RECOVERY: Display/GUI errors detected"
            print_info "Try setting DISPLAY manually: export DISPLAY=:0"
        fi
    fi
    
    # 3. Check if it's a venv issue
    if [ -f "$LOG_DIR/app.log" ]; then
        if grep -qi "no.*module.*named\|cannot.*import" "$LOG_DIR/app.log" 2>/dev/null; then
            print_warning "Missing packages detected - may need to reinstall dependencies"
            log_with_timestamp "RECOVERY: Missing packages detected"
            print_info "Try running: source venv/bin/activate && pip install -r requirements.txt"
        fi
    fi
    
    # 4. Check if it's a resource issue
    if command -v df >/dev/null 2>&1; then
        AVAILABLE_SPACE=$(df "$SCRIPT_DIR" | tail -1 | awk '{print $4}' 2>/dev/null || echo "0")
        if [ -n "$AVAILABLE_SPACE" ] && [ "$AVAILABLE_SPACE" -lt 51200 ]; then
            print_error "Critical: Very low disk space: ${AVAILABLE_SPACE}KB"
            log_with_timestamp "RECOVERY: Critical low disk space"
            print_info "Free up disk space and try again"
        fi
    fi
    
    # 5. Log recovery summary
    log_with_timestamp "RECOVERY: Recovery procedures completed"
    print_info "Recovery procedures completed - check logs for details"
    
    # Provide helpful error summary
    echo ""
    print_error "Application failed to start. Common solutions:"
    echo "  1. Check application logs: $LOG_DIR/app.log"
    echo "  2. Verify permissions: chmod +r $APP_FILE"
    echo "  3. Verify venv: source venv/bin/activate && pip install -r requirements.txt"
    echo "  4. Check DISPLAY: export DISPLAY=:0"
    echo "  5. Check disk space: df -h"
    echo "  6. Try manual run: ./run-application-manual.sh"
    echo ""
}

# Function to check for critical startup errors
check_startup_errors() {
    if [ ! -f "$LOG_DIR/app.log" ]; then
        return 0  # Log file doesn't exist yet
    fi
    
    # Check for critical errors that indicate the app won't start
    local critical_errors=0
    
    # Check for import errors
    if grep -qi "import.*error\|module.*not.*found\|cannot.*import\|no.*module.*named" "$LOG_DIR/app.log" 2>/dev/null; then
        log_with_timestamp "ERROR: Import/module errors detected in app.log"
        critical_errors=$((critical_errors + 1))
    fi
    
    # Check for syntax errors
    if grep -qi "syntax.*error\|indentation.*error" "$LOG_DIR/app.log" 2>/dev/null; then
        log_with_timestamp "ERROR: Syntax errors detected in app.log"
        critical_errors=$((critical_errors + 1))
    fi
    
    # Check for display/GUI errors
    if grep -qi "cannot.*connect.*to.*x.*server\|no.*display\|qt.*platform.*plugin" "$LOG_DIR/app.log" 2>/dev/null; then
        log_with_timestamp "ERROR: Display/GUI errors detected in app.log"
        critical_errors=$((critical_errors + 1))
    fi
    
    # Check for file not found errors (certificates, etc.)
    if grep -qi "file.*not.*found\|no.*such.*file\|certificate.*not.*found" "$LOG_DIR/app.log" 2>/dev/null; then
        log_with_timestamp "ERROR: File not found errors detected in app.log"
        critical_errors=$((critical_errors + 1))
    fi
    
    # Check for virtual environment errors
    if grep -qi "failed.*to.*activate.*virtual.*environment\|not.*using.*venv.*python\|python.*not.*found.*in.*path\|required.*packages.*not.*found.*in.*venv" "$LOG_DIR/app.log" 2>/dev/null; then
        log_with_timestamp "ERROR: Virtual environment errors detected in app.log"
        critical_errors=$((critical_errors + 1))
    fi
    
    # Check for module/package errors that might indicate venv issues
    if grep -qi "no.*module.*named.*PyQt6\|no.*module.*named.*awsiot\|cannot.*import.*PyQt6\|cannot.*import.*awsiot" "$LOG_DIR/app.log" 2>/dev/null; then
        log_with_timestamp "ERROR: Missing required packages (PyQt6/awsiot) - venv may not be properly activated"
        critical_errors=$((critical_errors + 1))
    fi
    
    if [ "$critical_errors" -gt 0 ]; then
        log_with_timestamp "ERROR: Found $critical_errors critical startup error(s)"
        return 1
    fi
    
    return 0
}

# Wait and verify process started successfully
log_with_timestamp "START: Waiting 3 seconds to verify process started"
sleep 3

# Check for immediate errors in logs (before checking process status)
if [ -f "$LOG_DIR/app.log" ]; then
    log_with_timestamp "START: Checking for immediate startup errors in logs"
    if ! check_startup_errors; then
        print_error "Critical startup errors detected in application logs"
        log_with_timestamp "ERROR: Critical startup errors found - application may not start properly"
        check_app_logs
        # Still check if process is running, but log the errors
    fi
fi

if check_app_status "$APP_PID" "initial"; then
    print_success "Application started successfully (PID: $APP_PID)"
    log_with_timestamp "START: Application started successfully (PID: $APP_PID)"
    log_process_info "Application (newly started)" "$APP_PID"
    
    # Check logs for errors
    if ! check_app_logs; then
        print_warning "Errors detected in application logs, but process is running"
        log_with_timestamp "WARNING: Errors in logs but process still running - monitoring closely"
    fi
    
    # Check for critical errors again after a moment
    sleep 2
    if ! check_startup_errors; then
        print_error "Critical errors detected - application may crash soon"
        log_with_timestamp "ERROR: Critical errors detected after initial start"
        check_app_logs
        # Continue monitoring but mark as potentially unstable
    fi
    
    # Extended monitoring - check multiple times over 30 seconds (increased from 10)
    log_with_timestamp "START: Starting extended monitoring (checking every 3 seconds for 30 seconds)"
    MONITORING_PASSED=true
    ERROR_DETECTED=false
    for i in 1 2 3 4 5 6 7 8 9 10; do
        sleep 3
        if ! check_app_status "$APP_PID" "monitor-$i"; then
            print_error "Application crashed during monitoring (check $i/10)"
            log_with_timestamp "ERROR: Application crashed during monitoring at check $i/10"
            MONITORING_PASSED=false
            check_app_logs
            break
        fi
        
        # Check for errors in logs during monitoring
        if ! check_startup_errors; then
            if [ "$ERROR_DETECTED" = false ]; then
                print_warning "Errors detected in logs during monitoring (check $i/10)"
                log_with_timestamp "WARNING: Errors detected during monitoring at check $i/10"
                ERROR_DETECTED=true
                check_app_logs
            fi
        fi
        
        log_with_timestamp "STATUS: Application still running after $((i * 3)) seconds"
    done
    
    if [ "$MONITORING_PASSED" = true ]; then
        print_success "Verified: Application is running stably (survived 30+ seconds)"
        log_with_timestamp "START: Verified - Application is running stably"
        
        # Final error check before declaring success
        if ! check_startup_errors; then
            print_warning "Errors detected in logs, but application is still running"
            log_with_timestamp "WARNING: Errors in logs but process stable - may need attention"
        fi
        
        # Check if we can see the process command to verify it's using the correct file
        if command -v ps >/dev/null 2>&1; then
            PROCESS_CMD=$(ps -p "$APP_PID" -o command= 2>/dev/null || echo "")
            log_with_timestamp "START: Process command: $PROCESS_CMD"
            if echo "$PROCESS_CMD" | grep -q "iot_pubsub_gui.py"; then
                print_info "Process verified: Running iot_pubsub_gui.py"
                log_with_timestamp "START: Process verified - running iot_pubsub_gui.py"
            fi
            
            # Log detailed process information
            log_process_info "Application (running)" "$APP_PID"
        fi
        
        # Log file information again to confirm we're using the latest
        log_file_info "$APP_FILE"
        
        # Final stability check after another 10 seconds (increased from 5)
        log_with_timestamp "START: Final stability check (waiting 10 more seconds)"
        sleep 10
        if check_app_status "$APP_PID" "final"; then
            # One more error check
            if check_startup_errors; then
                print_success "Application is running stably (survived 40+ seconds, no critical errors)"
                log_with_timestamp "START: Application passed final stability check - no critical errors"
            else
                print_warning "Application is running but errors detected in logs"
                log_with_timestamp "WARNING: Application running but errors in logs - may need investigation"
            fi
        else
            print_error "Application crashed after extended stability check"
            log_with_timestamp "ERROR: Application crashed after extended stability check"
            check_app_logs
            attempt_recovery "$APP_PID"
            rm -f "$PID_FILE"
            exit 1
        fi
    else
        print_error "Application failed stability check - crashed during monitoring"
        log_with_timestamp "ERROR: Application failed stability check"
        check_app_logs
        attempt_recovery "$APP_PID"
        rm -f "$PID_FILE"
        exit 1
    fi
    
    print_info "Application logs: $LOG_DIR/app.log"
    print_info "Update logs: $LOG_FILE"
    log_with_timestamp "START: Application successfully running with PID $APP_PID"
else
    print_error "Application failed to start (PID: $APP_PID)"
    log_with_timestamp "ERROR: Application failed to start (PID: $APP_PID not found)"
    print_info "Check application logs: $LOG_DIR/app.log"
    check_app_logs
    
    # Attempt recovery
    attempt_recovery "$APP_PID"
    
    # Provide detailed diagnostics
    echo ""
    print_error "=== Startup Failure Diagnostics ==="
    echo "Application PID: $APP_PID"
    echo "Application file: $APP_FILE"
    echo "Application file exists: $([ -f "$APP_FILE" ] && echo "Yes" || echo "No")"
    echo "Application file readable: $([ -r "$APP_FILE" ] && echo "Yes" || echo "No")"
    echo "Venv Python: $VENV_PYTHON"
    echo "Venv Python exists: $([ -f "$VENV_PYTHON" ] && echo "Yes" || echo "No")"
    echo "Venv Python executable: $([ -x "$VENV_PYTHON" ] && echo "Yes" || echo "No")"
    echo "Working directory: $(pwd)"
    echo "DISPLAY: ${DISPLAY:-not set}"
    echo "USER: ${USER:-not set}"
    echo "HOME: ${HOME:-not set}"
    echo "PATH: $PATH"
    echo ""
    
    if [ -f "$LOG_DIR/app.log" ]; then
        echo "Last 20 lines of app.log:"
        tail -20 "$LOG_DIR/app.log" 2>/dev/null || echo "Could not read app.log"
        echo ""
    fi
    
    rm -f "$PID_FILE"
    exit 1
fi

# ============================================================================
# Step 8: Restart webhook listener service (if running as systemd service)
# ============================================================================
print_step "Step 6: Restarting Webhook Listener Service"

WEBHOOK_SERVICE="iot-gui-webhook.service"

# Check if systemd service exists and is enabled
if systemctl list-unit-files | grep -q "$WEBHOOK_SERVICE"; then
    print_info "Webhook listener service found: $WEBHOOK_SERVICE"
    
    # Check if service is active
    log_with_timestamp "SERVICE: Checking webhook listener service status"
    if systemctl is-active --quiet "$WEBHOOK_SERVICE"; then
        print_info "Restarting webhook listener service..."
        log_with_timestamp "SERVICE: Restarting $WEBHOOK_SERVICE"
        if sudo systemctl restart "$WEBHOOK_SERVICE" 2>&1 | tee -a "$LOG_FILE"; then
            sleep 2  # Wait a moment for service to restart
            log_with_timestamp "SERVICE: Waiting 2 seconds for service to restart"
            if systemctl is-active --quiet "$WEBHOOK_SERVICE"; then
                print_success "Webhook listener service restarted successfully"
                log_with_timestamp "SERVICE: Webhook listener service restarted successfully"
                
                # Log service process info
                SERVICE_PID=$(systemctl show -p MainPID --value "$WEBHOOK_SERVICE" 2>/dev/null || echo "")
                if [ -n "$SERVICE_PID" ] && [ "$SERVICE_PID" != "0" ]; then
                    log_process_info "Webhook listener service" "$SERVICE_PID"
                fi
            else
                print_warning "Webhook listener service restarted but may not be active"
                log_with_timestamp "WARNING: Webhook listener service status unclear"
            fi
        else
            print_warning "Failed to restart webhook listener service (may require sudo)"
            log_with_timestamp "WARNING: Failed to restart webhook listener service"
        fi
    else
        print_info "Webhook listener service is not active, attempting to start..."
        log_with_timestamp "SERVICE: Starting $WEBHOOK_SERVICE (was not active)"
        if sudo systemctl start "$WEBHOOK_SERVICE" 2>&1 | tee -a "$LOG_FILE"; then
            print_success "Webhook listener service started"
            log_with_timestamp "SERVICE: Webhook listener service started"
            
            # Log service process info
            SERVICE_PID=$(systemctl show -p MainPID --value "$WEBHOOK_SERVICE" 2>/dev/null || echo "")
            if [ -n "$SERVICE_PID" ] && [ "$SERVICE_PID" != "0" ]; then
                log_process_info "Webhook listener service" "$SERVICE_PID"
            fi
        else
            print_warning "Failed to start webhook listener service (may require sudo)"
            log_with_timestamp "WARNING: Failed to start webhook listener service"
        fi
    fi
else
    print_info "Webhook listener service not found or not installed as systemd service"
    print_info "If running webhook listener manually, restart it to pick up changes"
    log_with_timestamp "Webhook listener service not found - skipping restart"
fi

# ============================================================================
# Summary
# ============================================================================
print_step "Update and Restart Complete"

if [ "$CODE_UPDATED" = true ]; then
    print_success "Code updated and application restarted"
    log_with_timestamp "SUMMARY: Code updated and application restarted"
else
    print_success "Application restarted (no code changes)"
    log_with_timestamp "SUMMARY: Application restarted (no code changes)"
fi

print_info "Application PID: $APP_PID"
print_info "Application logs: $LOG_DIR/app.log"
print_info "Update logs: $LOG_FILE"
print_info "PID file: $PID_FILE"

# Final verification and logging
log_with_timestamp "SUMMARY: Final application status"
log_process_info "Application (final)" "$APP_PID"
log_file_info "$APP_FILE"
log_file_info "$PID_FILE"
log_git_info

log_with_timestamp "=== Update and Restart Completed Successfully ==="
log_with_timestamp "END: Script execution completed at $(date '+%Y-%m-%d %H:%M:%S')"

exit 0

