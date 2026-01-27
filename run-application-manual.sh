#!/bin/bash
# ============================================================================
# AWS IoT Pub/Sub GUI - Manual Run Script
# ============================================================================
# This script allows you to manually run the application with the latest code:
#   1. Pulls latest code from GitHub (main branch)
#   2. Updates Python dependencies if requirements.txt changed
#   3. Runs the application in foreground (so you can see errors)
#
# Usage:
#   ./run-application-manual.sh
#
# This is useful for:
#   - Testing new code changes before automatic deployment
#   - Debugging issues by seeing errors directly
#   - Running the application manually with latest code
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

print_step() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Get the script directory (project root)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration
VENV_DIR="$SCRIPT_DIR/venv"
APP_FILE="$SCRIPT_DIR/iot_pubsub_gui.py"
REQUIREMENTS_FILE="$SCRIPT_DIR/requirements.txt"
GIT_BRANCH="${GIT_BRANCH:-main}"

print_step "Manual Application Run - Getting Latest Code"

# ============================================================================
# Step 1: Check if we're in a git repository
# ============================================================================
if [ ! -d ".git" ]; then
    print_warning "Not a git repository. Skipping git pull."
    print_info "Will use existing code in the directory."
else
    # ============================================================================
    # Step 2: Pull latest code from GitHub (main branch)
    # ============================================================================
    print_step "Step 1: Pulling Latest Code from Main Branch"
    
    GIT_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
    if [ -z "$GIT_REMOTE" ]; then
        print_warning "No git remote 'origin' found. Skipping git pull."
        print_info "Will use existing code in the directory."
    else
        print_info "Git remote: $GIT_REMOTE"
        
        # Ensure we're on the main branch
        CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
        if [ -z "$CURRENT_BRANCH" ] || [ "$CURRENT_BRANCH" != "$GIT_BRANCH" ]; then
            print_info "Current branch: $CURRENT_BRANCH, switching to $GIT_BRANCH..."
            if git checkout "$GIT_BRANCH" 2>&1; then
                print_success "Switched to $GIT_BRANCH branch"
            else
                print_warning "Could not switch to $GIT_BRANCH, continuing with current branch..."
            fi
        else
            print_info "Already on $GIT_BRANCH branch"
        fi
        
        print_info "Fetching latest changes from origin/$GIT_BRANCH..."
        
        # Check if using SSH and set up SSH key if needed
        if echo "$GIT_REMOTE" | grep -q "^git@"; then
            SSH_KEY="$SCRIPT_DIR/id_ed25519_repo_pideployment"
            if [ -f "$SSH_KEY" ]; then
                print_info "Using SSH key for git operations: $SSH_KEY"
                export GIT_SSH_COMMAND="ssh -i $SSH_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"
            fi
        fi
        
        # Fetch latest changes
        if git fetch origin "$GIT_BRANCH" 2>&1; then
            print_success "Fetched latest changes"
        else
            print_warning "Failed to fetch from git, trying without SSH key..."
            unset GIT_SSH_COMMAND
            if ! git fetch origin "$GIT_BRANCH" 2>&1; then
                print_warning "Failed to fetch from git. Continuing with existing code..."
            fi
        fi
        
        # Pull latest code
        print_info "Pulling latest code from origin/$GIT_BRANCH..."
        if git pull origin "$GIT_BRANCH" 2>&1; then
            print_success "Pulled latest code successfully"
        else
            print_warning "Failed to pull with current config, trying without SSH key..."
            unset GIT_SSH_COMMAND
            if git pull origin "$GIT_BRANCH" 2>&1; then
                print_success "Pulled latest code successfully (without SSH key)"
            else
                print_warning "Failed to pull from git. Continuing with existing code..."
            fi
        fi
    fi
fi

# ============================================================================
# Step 3: Check if virtual environment exists
# ============================================================================
print_step "Step 2: Checking Virtual Environment"

if [ ! -d "$VENV_DIR" ]; then
    print_warning "Virtual environment not found at: $VENV_DIR"
    print_info "Creating virtual environment..."
    
    if ! python3 -m venv "$VENV_DIR"; then
        print_error "Failed to create virtual environment"
        exit 1
    fi
    
    print_success "Virtual environment created"
else
    print_info "Virtual environment found at: $VENV_DIR"
fi

# Activate virtual environment
print_info "Activating virtual environment..."
source "$VENV_DIR/bin/activate" || {
    print_error "Failed to activate virtual environment"
    exit 1
}

# ============================================================================
# Step 4: Update Python dependencies
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
    if python -m pip install --upgrade -r "$REQUIREMENTS_FILE" 2>&1; then
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
# Step 5: Check if application file exists
# ============================================================================
print_step "Step 4: Verifying Application File"

if [ ! -f "$APP_FILE" ]; then
    print_error "Application file not found: $APP_FILE"
    exit 1
fi

print_success "Application file found: $APP_FILE"

# ============================================================================
# Step 6: Check DISPLAY for GUI
# ============================================================================
print_step "Step 5: Checking Display Configuration"

if [ -z "$DISPLAY" ]; then
    # Try to set DISPLAY if in desktop session
    if [ -n "$XDG_SESSION_ID" ] || [ -n "$WAYLAND_DISPLAY" ]; then
        export DISPLAY=:0 2>/dev/null || true
        print_info "Set DISPLAY=:0 for GUI"
    else
        print_warning "DISPLAY not set - GUI may not work"
        print_warning "If running via SSH, use: ssh -X pi@raspberrypi-ip"
        print_warning "Or set manually: export DISPLAY=:0"
        echo ""
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Exiting. Set DISPLAY and try again."
            exit 1
        fi
    fi
else
    print_info "DISPLAY is set to: $DISPLAY"
fi

# ============================================================================
# Step 7: Run the application
# ============================================================================
print_step "Step 6: Running Application"

print_info "Starting application: $APP_FILE"
print_info "Application will run in foreground - you'll see all output and errors"
print_info "Press Ctrl+C to stop the application"
echo ""

# Use Python from venv (explicit path for reliability)
VENV_PYTHON="$VENV_DIR/bin/python"
if [ ! -f "$VENV_PYTHON" ]; then
    print_error "Python not found in virtual environment: $VENV_PYTHON"
    exit 1
fi

# Run the application in foreground
print_info "Launching application..."
echo ""
echo "----------------------------------------"
echo ""

# Run the application and capture exit code
"$VENV_PYTHON" "$APP_FILE"
EXIT_CODE=$?

echo ""
echo "----------------------------------------"
echo ""

# ============================================================================
# Step 8: Report results
# ============================================================================
if [ $EXIT_CODE -eq 0 ]; then
    print_success "Application exited normally"
else
    print_error "Application exited with error code: $EXIT_CODE"
    echo ""
    echo "Common issues:"
    echo "1. Import errors - check if all dependencies are installed"
    echo "2. Certificate files missing or incorrect"
    echo "3. Network connectivity issues"
    echo "4. AWS IoT endpoint configuration"
    echo "5. Display/GUI issues (if running via SSH, use: ssh -X)"
    echo ""
    echo "Check the error messages above for details."
fi

# Deactivate virtual environment
deactivate 2>/dev/null || true

exit $EXIT_CODE

