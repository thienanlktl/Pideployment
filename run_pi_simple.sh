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

echo "Starting AWS IoT Pub/Sub GUI..."
echo ""

# Run the application (using python from venv)
python iot_pubsub_gui.py

