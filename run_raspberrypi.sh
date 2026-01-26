#!/bin/bash
# AWS IoT Pub/Sub GUI - Raspberry Pi Launcher
# Double-click this file or run: ./run_raspberrypi.sh

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/venv"

# Activate virtual environment
source "$VENV_DIR/bin/activate"

# Run the application
python iot_pubsub_gui.py
