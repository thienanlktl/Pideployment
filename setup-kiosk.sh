#!/bin/bash
# Fix Windows CRLF so script runs on Pi
cr=$(printf '\r'); grep -q "$cr" "$0" 2>/dev/null && { sed -i "s/${cr}\$//" "$0"; exec bash "$0" "$@"; }
#
# =============================================================================
# IoT PubSub GUI - Full Kiosk Setup (one script for all steps)
# =============================================================================
# Runs on Raspberry Pi OS 64-bit Bookworm+ with Wayland/labwc.
# Usage: bash setup-kiosk.sh [OPTIONS]
#
# Options:
#   --app-dir DIR       App directory (default: /home/pi/iot-pubsub-gui)
#   --no-raspi-config   Skip raspi-config (autologin, overlay)
#   --no-rcxml          Skip labwc rc.xml (disable Alt+Tab/Alt+F4)
#   --overlayfs         Enable overlay file system (read-only root)
#   --ssh-key-only      Disable SSH password authentication (use key only)
#   --reboot            Reboot at the end
#   --clone             Clone repo to app-dir if it does not exist (uses SSH from ~/.ssh)
#   --clone-https       Same as --clone but use HTTPS (no SSH key needed; use for public repo)
#
# Clone uses: git@github.com:thienanlktl/Pideployment.git (SSH). Ensure ~/.ssh has your
# private key and the public key is added to GitHub/GitLab so --clone works on a fresh Pi.
# =============================================================================

set -e

APP_DIR="${APP_DIR:-/home/pi/iot-pubsub-gui}"
REPO_URL_SSH="${REPO_URL_SSH:-git@github.com:thienanlktl/Pideployment.git}"
REPO_URL_HTTPS="${REPO_URL_HTTPS:-https://github.com/thienanlktl/Pideployment.git}"
DO_RASPI_CONFIG=1
DO_RCXML=1
DO_OVERLAYFS=0
DO_SSH_KEY_ONLY=0
DO_REBOOT=0
DO_CLONE=0
CLONE_HTTPS=0

while [ $# -gt 0 ]; do
    case "$1" in
        --app-dir)      APP_DIR="$2"; shift 2 ;;
        --no-raspi-config) DO_RASPI_CONFIG=0; shift ;;
        --no-rcxml)     DO_RCXML=0; shift ;;
        --overlayfs)    DO_OVERLAYFS=1; shift ;;
        --ssh-key-only) DO_SSH_KEY_ONLY=1; shift ;;
        --reboot)       DO_REBOOT=1; shift ;;
        --clone)        DO_CLONE=1; shift ;;
        --clone-https)  DO_CLONE=1; CLONE_HTTPS=1; shift ;;
        *) echo "Unknown option: $1"; echo "Usage: $0 [--app-dir DIR] [--no-raspi-config] [--no-rcxml] [--overlayfs] [--ssh-key-only] [--reboot] [--clone] [--clone-https]"; exit 1 ;;
    esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
info()  { echo -e "${BLUE}[SETUP]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Must be Linux ---
if [ "$(uname -s)" != "Linux" ]; then
    err "This script is for Linux (Raspberry Pi OS)."
    exit 1
fi

# --- Do not run as root ---
if [ "$(id -u)" -eq 0 ]; then
    err "Do not run as root. Run as normal user (e.g. pi)."
    exit 1
fi

echo ""
echo "=============================================="
echo "  IoT PubSub GUI - Full Kiosk Setup"
echo "=============================================="
echo ""
info "App directory: $APP_DIR"
echo ""

# -----------------------------------------------------------------------------
# Optional: clone repo if app dir does not exist (SSH from ~/.ssh or HTTPS)
# -----------------------------------------------------------------------------
if [ "$DO_CLONE" -eq 1 ] && [ ! -d "$APP_DIR/.git" ]; then
    parent="$(dirname "$APP_DIR")"
    mkdir -p "$parent"
    if [ -d "$APP_DIR" ]; then
        err "Directory $APP_DIR exists but is not a git repo. Remove it or use without --clone."
        exit 1
    fi
    if [ "$CLONE_HTTPS" -eq 1 ]; then
        info "Cloning repository (HTTPS) to $APP_DIR ..."
        git clone -b main "$REPO_URL_HTTPS" "$APP_DIR" || {
            err "Clone failed. Check network and repo URL: $REPO_URL_HTTPS"
            exit 1
        }
    else
        info "Cloning repository (SSH, using keys from ~/.ssh) to $APP_DIR ..."
        if [ ! -d "$HOME/.ssh" ]; then
            err "No ~/.ssh directory. Create one and add your private key, or use --clone-https."
            exit 1
        fi
        if ! ls "$HOME/.ssh"/id_*.pub 1>/dev/null 2>&1; then
            warn "No public key found in ~/.ssh (id_ed25519.pub, id_rsa.pub, etc.). Add your key and ensure the public key is added to GitHub/GitLab, or use --clone-https."
        fi
        git clone -b main "$REPO_URL_SSH" "$APP_DIR" || {
            err "Clone failed. Ensure: (1) private key is in ~/.ssh, (2) public key is added to GitHub/GitLab, (3) ssh -T git@github.com works. Or use --clone-https for public repo."
            exit 1
        }
    fi
    ok "Repository cloned."
fi

# -----------------------------------------------------------------------------
# Check app directory exists and has required files
# -----------------------------------------------------------------------------
if [ ! -d "$APP_DIR" ]; then
    err "App directory not found: $APP_DIR"
    echo "  Create it and copy the project files, or run with --clone to clone the repo."
    exit 1
fi

if [ ! -f "$APP_DIR/iot_pubsub_gui.py" ] || [ ! -f "$APP_DIR/ensure_venv.sh" ]; then
    err "Missing required files in $APP_DIR (iot_pubsub_gui.py, ensure_venv.sh)."
    exit 1
fi
ok "App directory OK."

# -----------------------------------------------------------------------------
# Phase 2: System packages
# -----------------------------------------------------------------------------
info "Installing system packages (unclutter, python3-venv, etc.) ..."
sudo apt-get update -qq
sudo apt-get install -y unclutter python3 python3-pip python3-venv python3-dev 2>/dev/null || true
ok "System packages installed."

# -----------------------------------------------------------------------------
# Phase 3: Virtual environment and Python packages
# -----------------------------------------------------------------------------
info "Setting up virtual environment and Python dependencies ..."
cd "$APP_DIR" || exit 1
chmod +x ensure_venv.sh monitor.sh 2>/dev/null || true
bash ./ensure_venv.sh
ok "Venv and packages ready."

# -----------------------------------------------------------------------------
# Phase 4: labwc autostart
# -----------------------------------------------------------------------------
info "Configuring labwc autostart ..."
mkdir -p "$HOME/.config/labwc"
cat > "$HOME/.config/labwc/autostart" << EOF
# labwc autostart for kiosk - generated by setup-kiosk.sh
APP_DIR="$APP_DIR"

# Ensure venv and all packages installed (creates venv if missing; idempotent)
[ -f "\$APP_DIR/venv/bin/python3" ] || (cd "\$APP_DIR" && bash ./ensure_venv.sh) || true

# Hide cursor when idle (0.1 second)
unclutter -idle 0.1 &

# Monitor: restart app if it crashes (checks every 10s); uses venv
"\$APP_DIR/monitor.sh" &

# Give labwc and unclutter a moment
sleep 2

# Start kiosk app with venv (fullscreen, no exit keys). Monitor will restart if it exits.
"\$APP_DIR/venv/bin/python3" "\$APP_DIR/iot_pubsub_gui.py" --kiosk &
EOF
chmod +x "$HOME/.config/labwc/autostart"
ok "labwc autostart installed at ~/.config/labwc/autostart"

# -----------------------------------------------------------------------------
# Phase 5: labwc rc.xml (disable Alt+Tab, Alt+F4)
# -----------------------------------------------------------------------------
if [ "$DO_RCXML" -eq 1 ]; then
    info "Configuring labwc rc.xml (disable escape shortcuts) ..."
    if [ -f "$HOME/.config/labwc/rc.xml" ]; then
        cp "$HOME/.config/labwc/rc.xml" "$HOME/.config/labwc/rc.xml.bak"
    fi
    if [ -f /etc/xdg/labwc/rc.xml ]; then
        cp /etc/xdg/labwc/rc.xml "$HOME/.config/labwc/rc.xml"
        # Remove A-Tab and A-F4 keybind blocks (disable Alt+Tab, Alt+F4)
        sed -i '/<keybind key="A-Tab">/,/<\/keybind>/d' "$HOME/.config/labwc/rc.xml" 2>/dev/null || true
        sed -i '/<keybind key="A-F4">/,/<\/keybind>/d' "$HOME/.config/labwc/rc.xml" 2>/dev/null || true
        ok "labwc rc.xml updated (~/.config/labwc/rc.xml)"
    else
        warn "System rc.xml not found (/etc/xdg/labwc/rc.xml). Skip or edit ~/.config/labwc/rc.xml manually."
    fi
else
    info "Skipping rc.xml (--no-rcxml). Edit ~/.config/labwc/rc.xml manually to disable Alt+Tab, Alt+F4."
fi

# -----------------------------------------------------------------------------
# Phase 6: raspi-config (autologin, optional overlay)
# -----------------------------------------------------------------------------
if [ "$DO_RASPI_CONFIG" -eq 1 ]; then
    info "Setting Desktop Autologin via raspi-config ..."
    if command -v raspi-config >/dev/null 2>&1; then
        sudo raspi-config nonint do_boot_behaviour B4 || true
        ok "Desktop Autologin enabled (B4)."
        if [ "$DO_OVERLAYFS" -eq 1 ]; then
            info "Enabling Overlay File System (read-only root) ..."
            sudo raspi-config nonint do_overlayfs 0 || true
            ok "Overlay FS enabled."
        fi
    else
        warn "raspi-config not found. Enable Desktop Autologin manually (raspi-config -> Boot / Auto Login -> Desktop Autologin)."
    fi
else
    info "Skipping raspi-config (--no-raspi-config)."
fi

# -----------------------------------------------------------------------------
# Phase 7 (optional): SSH key-only
# -----------------------------------------------------------------------------
if [ "$DO_SSH_KEY_ONLY" -eq 1 ]; then
    warn "Disabling SSH password authentication (key-only). Ensure you can log in with a key first!"
    sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null || true
    sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sudo sed -i 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
    sudo systemctl restart ssh 2>/dev/null || true
    ok "SSH password auth disabled. Test key login before closing this session."
fi

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  Kiosk setup complete"
echo "=============================================="
echo ""
echo "  App directory:    $APP_DIR"
echo "  labwc autostart:  $HOME/.config/labwc/autostart"
echo "  labwc rc.xml:     $HOME/.config/labwc/rc.xml"
echo ""
if [ "$DO_RASPI_CONFIG" -eq 1 ]; then
    echo "  Autologin is enabled. After reboot, the Pi will log in and start the kiosk app."
fi
echo "  Reboot to start kiosk:  sudo reboot"
echo ""

if [ "$DO_REBOOT" -eq 1 ]; then
    warn "Rebooting in 5 seconds (Ctrl+C to cancel) ..."
    sleep 5
    sudo reboot
else
    info "To start kiosk now, reboot:  sudo reboot"
fi
