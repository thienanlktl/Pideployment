#!/bin/bash
# If file has Windows CRLF, re-run self with cleaned copy (no in-place edit; works when run as sh or bash)
cr=$(printf '\r'); grep -q "$cr" "$0" 2>/dev/null && { sed "s/${cr}\$//" "$0" > /tmp/build-deb-nocr.$$.sh; chmod +x /tmp/build-deb-nocr.$$.sh; exec bash /tmp/build-deb-nocr.$$.sh "$@"; }
# Build a .deb package for IoT PubSub GUI (Raspberry Pi / Debian / Ubuntu).
# Run on the Pi: bash build-deb.sh   or   ./build-deb.sh
# Output: iot-pubsub-gui_<VERSION>_<arch>.deb

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f "VERSION" ]; then echo "ERROR: VERSION file not found in $SCRIPT_DIR"; exit 1; fi
for req in iot_pubsub_gui.py requirements.txt iot-pubsub-gui-launch.sh; do [ -f "$req" ] || { echo "ERROR: $req not found"; exit 1; }; done
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

# App files under /opt/iot-pubsub-gui (single-line loop to avoid CRLF breaking do/done)
mkdir -p "$PKG_ROOT"
for f in iot_pubsub_gui.py requirements.txt VERSION iot-pubsub-gui-launch.sh iot-pubsub-gui.svg; do [ -f "$f" ] && cp "$f" "$PKG_ROOT/"; done
chmod +x "$PKG_ROOT/iot-pubsub-gui-launch.sh" 2>/dev/null || true
sed -i 's/\r$//' "$PKG_ROOT/iot-pubsub-gui-launch.sh" 2>/dev/null || true

# Desktop file (system-wide; no heredoc to avoid CRLF breaking EOF delimiter)
mkdir -p "$DESKTOP_DIR"
{ printf '%s\n' '[Desktop Entry]' 'Version=1.0' 'Type=Application' 'Name=IoT PubSub GUI' 'Comment=AWS IoT Pub/Sub GUI for Raspberry Pi'
  printf '%s\n' "Exec=$INSTALL_PREFIX/iot-pubsub-gui-launch.sh" "Path=$INSTALL_PREFIX" "Icon=$INSTALL_PREFIX/iot-pubsub-gui.svg"
  printf '%s\n' 'Terminal=false' 'Categories=Network;Utility;' 'StartupNotify=true' 'Keywords=IoT;AWS;MQTT;PubSub;'; } > "$DESKTOP_DIR/iot-pubsub-gui.desktop"
sed -i 's/\r$//' "$DESKTOP_DIR/iot-pubsub-gui.desktop" 2>/dev/null || true

# Optional: icon for menu (scalable)
mkdir -p "$ICON_DIR"
[ -f "iot-pubsub-gui.svg" ] && cp "iot-pubsub-gui.svg" "$ICON_DIR/iot-pubsub-gui.svg"

# DEBIAN/control (no heredoc to avoid CRLF breaking EOF delimiter)
mkdir -p "$BUILD_ROOT/DEBIAN"
{ printf '%s\n' "Package: $APP_NAME" "Version: $VERSION" 'Section: net' 'Priority: optional' "Architecture: $ARCH"
  printf '%s\n' 'Depends: python3, python3-venv, python3-pip' 'Maintainer: IoT PubSub GUI <noreply@example.com>'
  printf '%s\n' 'Description: AWS IoT Pub/Sub GUI for Raspberry Pi' ' GUI application for AWS IoT Core MQTT pub/sub and device shadows.' ' Run from the application menu (IoT PubSub GUI).'; } > "$BUILD_ROOT/DEBIAN/control"

# DEBIAN/postinst: create venv and install Python deps
{ printf '%s\n' '#!/bin/sh' 'set -e' 'INSTALL_PREFIX="/opt/iot-pubsub-gui"'
  printf '%s\n' 'if [ -d "$INSTALL_PREFIX" ] && [ ! -f "$INSTALL_PREFIX/venv/bin/python3" ]; then'
  printf '%s\n' '    python3 -m venv "$INSTALL_PREFIX/venv"'
  printf '%s\n' '    "$INSTALL_PREFIX/venv/bin/pip" install -q -r "$INSTALL_PREFIX/requirements.txt" || true'
  printf '%s\n' 'fi'
  printf '%s\n' 'chown -R root:root "$INSTALL_PREFIX" 2>/dev/null || true'
  printf '%s\n' 'chmod -R a+rX "$INSTALL_PREFIX" 2>/dev/null || true'
  printf '%s\n' 'chmod +x "$INSTALL_PREFIX/iot-pubsub-gui-launch.sh" 2>/dev/null || true'
  printf '%s\n' 'if command -v update-desktop-database >/dev/null 2>&1; then'
  printf '%s\n' '    update-desktop-database /usr/share/applications 2>/dev/null || true'
  printf '%s\n' 'fi'; } > "$BUILD_ROOT/DEBIAN/postinst"
chmod 755 "$BUILD_ROOT/DEBIAN/postinst"

# Build .deb (Pi: do not add a blank line after exit 0)
dpkg-deb --root-owner-group -b "$BUILD_ROOT" "$DEB_NAME"
rm -rf "$BUILD_ROOT"
exit 0
