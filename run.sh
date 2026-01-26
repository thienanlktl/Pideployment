#!/bin/bash
# AWS IoT Pub/Sub GUI - Linux Launcher
# Double-click this file or run: ./run.sh

echo "========================================"
echo "AWS IoT Pub/Sub GUI - Feasibility Demo"
echo "========================================"
echo ""

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo "ERROR: Python 3 is not installed or not in PATH"
    echo "Please install Python 3.8 or higher"
    exit 1
fi

echo "Checking Python installation..."
python3 --version
echo ""

# Check if required packages are installed
echo "Checking required packages..."

if ! python3 -c "import PyQt6" &> /dev/null; then
    echo "PyQt6 not found. Installing..."
    python3 -m pip install PyQt6
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to install PyQt6"
        exit 1
    fi
fi

if ! python3 -c "import awsiot" &> /dev/null; then
    echo "awsiotsdk not found. Installing..."
    python3 -m pip install awsiotsdk
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to install awsiotsdk"
        exit 1
    fi
fi

echo "All dependencies are installed."
echo ""

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
else
    echo "Not a git repository, skipping git pull"
fi

echo ""
echo "Starting application..."
echo ""

# Run the application
python3 iot_pubsub_gui.py

# Check exit status
if [ $? -ne 0 ]; then
    echo ""
    echo "Application exited with an error."
    read -p "Press Enter to exit..."
fi

