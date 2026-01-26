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

