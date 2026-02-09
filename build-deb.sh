#!/bin/bash
# Build a .deb package for IoT PubSub GUI (Raspberry Pi / Debian / Ubuntu).
# Run on the Pi or any Debian/Ubuntu machine. Output: iot-pubsub-gui_<VERSION>_<arch>.deb
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Fix CRLF if this script was edited on Windows
grep -q $'\r' "$0" 2>/dev/null && { sed -i 's/\r$//' "$0"; exec bash "$0" "$@"; }

if [ ! -f "VERSION" ]; then
    echo "ERROR: VERSION file not found in $SCRIPT_DIR"
    exit 1
fi
VERSION=$(cat VERSION | tr -d '\r\n ')
APP_NAME="iot-pubsub-gui"
INSTALL_PREFIX="/opt/iot-pubsub-gui"
ARCH=$(dpkg --print-architecture 2>/dev/null || echo "all")
DEB_NAME="${APP_NAME}_${VERSION}_${ARCH}.deb"
BUILD_ROOT="$(mktemp -d)"
PKG_ROOT="$BUILD_ROOT/${INSTALL_PREFIX#/}"
DESKTOP_DIR="$BUILD_ROOT/usr/share/applications"
ICON_DIR="$BUILD_ROOT/usr/share/icons/hicolor/scalable/apps"

echo "Building $DEB_NAME (version $VERSION, arch $ARCH) ..."

# App files under /opt/iot-pubsub-gui
mkdir -p "$PKG_ROOT"
for f in iot_pubsub_gui.py requirements.txt VERSION iot-pubsub-gui-launch.sh iot-pubsub-gui.svg; do
    [ -f "$f" ] && cp "$f" "$PKG_ROOT/"
done
chmod +x "$PKG_ROOT/iot-pubsub-gui-launch.sh" 2>/dev/null || true
sed -i 's/\r$//' "$PKG_ROOT/iot-pubsub-gui-launch.sh" 2>/dev/null || true

# Desktop file (system-wide; uses /opt path)
mkdir -p "$DESKTOP_DIR"
cat > "$DESKTOP_DIR/iot-pubsub-gui.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=IoT PubSub GUI
Comment=AWS IoT Pub/Sub GUI for Raspberry Pi
Exec=$INSTALL_PREFIX/iot-pubsub-gui-launch.sh
Path=$INSTALL_PREFIX
Icon=$INSTALL_PREFIX/iot-pubsub-gui.svg
Terminal=false
Categories=Network;Utility;
StartupNotify=true
Keywords=IoT;AWS;MQTT;PubSub;
EOF
sed -i 's/\r$//' "$DESKTOP_DIR/iot-pubsub-gui.desktop" 2>/dev/null || true

# Optional: icon for menu (scalable)
mkdir -p "$ICON_DIR"
[ -f "iot-pubsub-gui.svg" ] && cp "iot-pubsub-gui.svg" "$ICON_DIR/iot-pubsub-gui.svg"

# DEBIAN/control
mkdir -p "$BUILD_ROOT/DEBIAN"
cat > "$BUILD_ROOT/DEBIAN/control" << EOF
Package: $APP_NAME
Version: $VERSION
Section: net
Priority: optional
Architecture: $ARCH
Depends: python3, python3-venv, python3-pip
Maintainer: IoT PubSub GUI <noreply@example.com>
Description: AWS IoT Pub/Sub GUI for Raspberry Pi
 GUI application for AWS IoT Core MQTT pub/sub and device shadows.
 Run from the application menu (IoT PubSub GUI).
EOF

# DEBIAN/postinst: create venv and install Python deps
cat > "$BUILD_ROOT/DEBIAN/postinst" << 'POSTINST'
#!/bin/sh
set -e
INSTALL_PREFIX="/opt/iot-pubsub-gui"
if [ -d "$INSTALL_PREFIX" ] && [ ! -f "$INSTALL_PREFIX/venv/bin/python3" ]; then
    python3 -m venv "$INSTALL_PREFIX/venv"
    "$INSTALL_PREFIX/venv/bin/pip" install -q -r "$INSTALL_PREFIX/requirements.txt" || true
fi
chown -R root:root "$INSTALL_PREFIX" 2>/dev/null || true
chmod -R a+rX "$INSTALL_PREFIX" 2>/dev/null || true
chmod +x "$INSTALL_PREFIX/iot-pubsub-gui-launch.sh" 2>/dev/null || true
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications 2>/dev/null || true
fi
POSTINST
chmod 755 "$BUILD_ROOT/DEBIAN/postinst"

# Build .deb
dpkg-deb --root-owner-group -b "$BUILD_ROOT" "$DEB_NAME"
rm -rf "$BUILD_ROOT"

echo "Done: $DEB_NAME"
echo "Install on Pi: sudo apt install -f ./$DEB_NAME"
