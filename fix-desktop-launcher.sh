#!/bin/bash
# Fix Desktop Launcher Script
# Run this if the desktop icon doesn't work

INSTALL_DIR="$HOME/iot-pubsub-gui"
DESKTOP_DIR="$HOME/Desktop"
DESKTOP_FILE="$DESKTOP_DIR/iot-pubsub-gui.desktop"
WRAPPER_SCRIPT="$INSTALL_DIR/run-iot-pubsub-gui.sh"

echo "Fixing IoT PubSub GUI Desktop Launcher..."
echo ""

# Check if installation directory exists
if [ ! -d "$INSTALL_DIR" ]; then
    echo "ERROR: Installation directory not found: $INSTALL_DIR"
    echo "Please run the installer first."
    exit 1
fi

# Create wrapper script
echo "Creating wrapper script..."
cat > "$WRAPPER_SCRIPT" << 'WRAPPER_EOF'
#!/bin/bash
# Wrapper script for IoT PubSub GUI
INSTALL_DIR="$HOME/iot-pubsub-gui"
cd "$INSTALL_DIR" || {
    echo "Error: Cannot change to directory $INSTALL_DIR"
    read -p "Press Enter to exit..."
    exit 1
}

if [ ! -f "venv/bin/activate" ]; then
    echo "Error: Virtual environment not found"
    read -p "Press Enter to exit..."
    exit 1
fi

source venv/bin/activate || {
    echo "Error: Cannot activate virtual environment"
    read -p "Press Enter to exit..."
    exit 1
}

python3 iot_pubsub_gui.py "$@"
WRAPPER_EOF

chmod +x "$WRAPPER_SCRIPT"
echo "✓ Wrapper script created: $WRAPPER_SCRIPT"

# Ensure Desktop directory exists
mkdir -p "$DESKTOP_DIR"

# Create desktop launcher
echo "Creating desktop launcher..."
cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=IoT PubSub GUI
Comment=Launch IoT PubSub GUI Application
Exec=$WRAPPER_SCRIPT
Path=$INSTALL_DIR
Icon=application-x-executable
Terminal=true
Categories=Network;Utility;
StartupNotify=true
Keywords=IoT;AWS;MQTT;PubSub;
EOF

# Make launcher executable
chmod +x "$DESKTOP_FILE"
echo "✓ Desktop launcher created: $DESKTOP_FILE"

# Make desktop file trusted (required for some desktop environments)
if command -v gio &> /dev/null; then
    gio set "$DESKTOP_FILE" metadata::trusted true 2>/dev/null && echo "✓ Desktop file marked as trusted"
fi

# Copy to applications directory
if [ -d "$HOME/.local/share/applications" ]; then
    cp "$DESKTOP_FILE" "$HOME/.local/share/applications/" 2>/dev/null && echo "✓ Copied to applications directory"
fi

# Refresh desktop
if command -v update-desktop-database &> /dev/null; then
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null && echo "✓ Desktop database updated"
fi

echo ""
echo "Desktop launcher fixed!"
echo ""
echo "To test, try:"
echo "  1. Double-click the desktop icon"
echo "  2. Or run: $WRAPPER_SCRIPT"
echo "  3. Or run: bash $DESKTOP_FILE"
echo ""

