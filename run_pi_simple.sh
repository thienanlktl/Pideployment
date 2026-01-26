#!/bin/bash
# AWS IoT Pub/Sub GUI - Raspberry Pi Simple Launcher
# Quick one-click launcher for Raspberry Pi

cd "$(dirname "$0")"

# Get the script directory
SCRIPT_DIR="$(pwd)"
VENV_DIR="$SCRIPT_DIR/venv"

# Check if virtual environment exists
if [ ! -d "$VENV_DIR" ]; then
    echo "ERROR: Virtual environment not found!"
    echo "Please run: sudo ./install_raspberrypi.sh"
    exit 1
fi

# Activate virtual environment
source "$VENV_DIR/bin/activate"

# Pull latest code from git if in a git repository
if [ -d ".git" ]; then
    echo "Pulling latest code from git..."
    GIT_BRANCH="${GIT_BRANCH:-main}"
    
    # Check git remote configuration
    GIT_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
    if [ -n "$GIT_REMOTE" ]; then
        echo "Git remote: $GIT_REMOTE"
        
        # Ensure we're on the correct branch
        CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
        if [ -n "$CURRENT_BRANCH" ] && [ "$CURRENT_BRANCH" != "$GIT_BRANCH" ]; then
            echo "Switching to $GIT_BRANCH branch..."
            git checkout "$GIT_BRANCH" 2>/dev/null || echo "Warning: Could not switch to $GIT_BRANCH"
        fi
        
        # Pull latest code
        if git pull origin "$GIT_BRANCH" 2>/dev/null; then
            echo "Successfully pulled latest code from git"
        else
            echo "Warning: Failed to pull latest code from git, continuing with current code..."
        fi
    else
        echo "Warning: No git remote found, skipping git pull"
    fi
    echo ""
fi

echo "Starting AWS IoT Pub/Sub GUI..."
echo ""

# Run the application (using python from venv)
python iot_pubsub_gui.py

