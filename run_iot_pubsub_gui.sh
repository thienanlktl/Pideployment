#!/bin/bash
# Launcher script for IoT PubSub GUI
# This script ensures the application runs with the correct virtual environment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check if virtual environment exists
if [ -d "venv" ]; then
    # Activate virtual environment
    source venv/bin/activate
    
    # Run the application
    python3 iot_pubsub_gui.py
else
    echo "ERROR: Virtual environment not found!"
    echo "Please run the installer first or create a virtual environment:"
    echo "  python3 -m venv venv"
    echo "  source venv/bin/activate"
    echo "  pip install -r requirements.txt"
    exit 1
fi

