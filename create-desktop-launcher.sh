#!/bin/bash
# Helper script to create desktop launcher with correct path
# Run this once to create a desktop launcher on your Desktop

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_FILE="$HOME/Desktop/iot-pubsub-gui.desktop"

cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=AWS IoT Pub/Sub GUI
Comment=Launch AWS IoT Pub/Sub GUI Application
Exec=bash -c "cd '$SCRIPT_DIR' && ./setup-and-run.sh"
Path=$SCRIPT_DIR
Icon=application-x-executable
Terminal=true
Categories=Network;Utility;
StartupNotify=true
Keywords=IoT;AWS;MQTT;PubSub;
EOF

chmod +x "$DESKTOP_FILE"

echo "Desktop launcher created at: $DESKTOP_FILE"
echo "You can now double-click it on your Desktop to launch the application!"

