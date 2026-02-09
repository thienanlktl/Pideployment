#!/bin/bash
grep -q $'\r' "$0" 2>/dev/null && { sed -i 's/\r$//' "$0"; exec bash "$0" "$@"; }
# =============================================================================
# IoT PubSub GUI - One-Click Installation for Raspberry Pi
# =============================================================================
# Safe to run multiple times (idempotent).
# Usage: bash install.sh
#
# FIRST-TIME: clones branch main. Re-run: pulls current branch (main or Release/* after in-app update).
# APP UPDATE: In-app updater in iot_pubsub_gui.py pulls from the latest Release/* branch (e.g. Release/1.0.4).
# CLONE USES EXISTING SSH FOLDER: All key files in .ssh (no subfolders). IOT_SSH_DIR / IOT_SSH_KEY optional.
# =============================================================================

set -e

# --- Configuration: clone from https://github.com/thienanlktl/Pideployment ---
REPO_URL="${IOT_REPO_URL:-https://github.com/thienanlktl/Pideployment.git}"
# First-time clone uses this branch (main). In-app update later pulls from latest Release/* branch.
BRANCH_MAIN="${IOT_BRANCH:-main}"
INSTALL_DIR="${IOT_INSTALL_DIR:-$HOME/iot-pubsub-gui}"
APP_NAME="IoT PubSub GUI"
# Optional: SSH folder (default: ~/.ssh) or path to one private key
IOT_SSH_DIR="${IOT_SSH_DIR:-}"
IOT_SSH_KEY="${IOT_SSH_KEY:-}"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Ensure bash ---
if [ -z "$BASH_VERSION" ]; then
    err "Run with bash: bash install.sh"
    exit 1
fi

# --- Don't run as root ---
if [ "$(id -u)" -eq 0 ]; then
    err "Do not run as root. Run as normal user; sudo will be used when needed."
    exit 1
fi

# --- Linux / Raspberry Pi OS ---
if [[ "$(uname -s)" != "Linux" ]]; then
    err "This script is for Linux (Raspberry Pi OS). Detected: $(uname -s)"
    exit 1
fi

echo ""
echo "=============================================="
echo "  $APP_NAME - One-Click Installer"
echo "=============================================="
echo ""
info "Install directory: $INSTALL_DIR"
info "Repository: $REPO_URL"
echo ""

# -----------------------------------------------------------------------------
# Step 1: System packages (fresh Pi: git, Python, build deps, GUI deps)
# -----------------------------------------------------------------------------
info "Checking system packages (required for fresh Raspberry Pi)..."

REQUIRED_PACKAGES=(
    git
    python3
    python3-pip
    python3-venv
    python3-dev
    build-essential
    sqlite3
    libsqlite3-dev
)
# Optional: help PyQt6 and SSL
OPTIONAL_PACKAGES=(
    libxcb-xinerama0
    libxkbcommon-x11-0
    libqt6gui6
    libqt6widgets6
    libqt6core6
    libgl1-mesa-glx
    libgl1
    libffi-dev
    libssl-dev
)

MISSING=()
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! dpkg -l 2>/dev/null | grep -qE "^ii[[:space:]]+$pkg([[:space:]]|:)"; then
        MISSING+=("$pkg")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    info "Updating package list..."
    sudo apt-get update -qq
    info "Installing required packages: ${MISSING[*]}"
    sudo apt-get install -y "${MISSING[@]}"
    ok "Required packages installed."
else
    ok "Required packages already installed."
fi

# Install optional packages (ignore errors for missing ones)
for pkg in "${OPTIONAL_PACKAGES[@]}"; do
    if ! dpkg -l 2>/dev/null | grep -qE "^ii[[:space:]]+$pkg([[:space:]]|:)"; then
        sudo apt-get install -y "$pkg" 2>/dev/null || true
    fi
done

# -----------------------------------------------------------------------------
# Step 2: Use existing SSH folder - find any private key file in .ssh (no subfolders)
# -----------------------------------------------------------------------------
# Get all public/private key files in the .ssh folder only (not in subfolders).
# Default: ~/.ssh. Override: IOT_SSH_DIR=/path/to/your/ssh/folder
SSH_DIR="${IOT_SSH_DIR:-$HOME/.ssh}"
SSH_KEY_FILE=""
if [ -d "$SSH_DIR" ]; then
    if [ -n "$IOT_SSH_KEY" ] && [ -f "$IOT_SSH_KEY" ]; then
        SSH_KEY_FILE="$IOT_SSH_KEY"
    else
        # Prefer standard names, then any other private key file in .ssh (not .pub, not config/known_hosts)
        for name in id_ed25519 id_rsa id_ecdsa; do
            if [ -f "$SSH_DIR/$name" ] && [ ! -d "$SSH_DIR/$name" ]; then
                SSH_KEY_FILE="$SSH_DIR/$name"
                break
            fi
        done
        if [ -z "$SSH_KEY_FILE" ]; then
            while IFS= read -r -d '' f; do
                base=$(basename "$f")
                [[ "$base" == *.pub ]] && continue
                [[ "$base" == config ]] && continue
                [[ "$base" == known_hosts ]] && continue
                [[ "$base" == authorized_keys ]] && continue
                [ -f "$f" ] && ! [ -d "$f" ] || continue
                grep -q "PRIVATE KEY" "$f" 2>/dev/null && { SSH_KEY_FILE="$f"; break; }
            done < <(find "$SSH_DIR" -maxdepth 1 -type f -print0 2>/dev/null)
        fi
    fi
fi

if [ -n "$SSH_KEY_FILE" ]; then
    chmod 600 "$SSH_KEY_FILE" 2>/dev/null || true
    export GIT_SSH_COMMAND="ssh -i '$SSH_KEY_FILE' -o StrictHostKeyChecking=accept-new -o BatchMode=yes"
    info "Using SSH folder: $SSH_DIR (private key files in folder only, no subfolders)"
    ok "Clone/update will use key: $SSH_KEY_FILE"
    # Convert HTTPS repo URL to SSH so git uses the key (no token prompt)
    if [[ "$REPO_URL" == https://github.com/* ]]; then
        REPO_PATH="${REPO_URL#https://github.com/}"
        REPO_PATH="${REPO_PATH%.git}"
        REPO_URL="git@github.com:${REPO_PATH}.git"
        ok "Using SSH URL: $REPO_URL"
    elif [[ "$REPO_URL" == https://gitlab.com/* ]]; then
        REPO_PATH="${REPO_URL#https://gitlab.com/}"
        REPO_PATH="${REPO_PATH%.git}"
        REPO_URL="git@gitlab.com:${REPO_PATH}.git"
        ok "Using SSH URL: $REPO_URL"
    elif [[ "$REPO_URL" == git@* ]] || [[ "$REPO_URL" == ssh://* ]]; then
        ok "Using SSH URL: $REPO_URL"
    fi
else
    if [[ "$REPO_URL" == git@* ]] || [[ "$REPO_URL" == ssh://* ]]; then
        err "SSH repo URL but no private key found in $SSH_DIR. Put public/private key files in that folder (not in a subfolder), or set IOT_SSH_DIR."
        exit 1
    fi
    warn "No private key found in $SSH_DIR; clone may prompt for credentials if repo is private."
fi

# -----------------------------------------------------------------------------
# Step 3: Clone or update repository
# -----------------------------------------------------------------------------
# First time: clone branch main. Later runs: pull current branch (main or Release/* after in-app update).
if [ -d "$INSTALL_DIR/.git" ]; then
    info "Repository already exists at $INSTALL_DIR; updating..."
    BRANCH="$(cd "$INSTALL_DIR" && git branch --show-current 2>/dev/null)" || BRANCH=""
    if [ -n "$BRANCH" ]; then
        if (cd "$INSTALL_DIR" && git fetch origin && git pull origin "$BRANCH"); then
            ok "Repository updated (branch: $BRANCH)."
        else
            warn "Could not pull (check credentials or network). Continuing with existing files."
        fi
    else
        warn "Could not detect branch; skipping pull."
    fi
else
    if [ -d "$INSTALL_DIR" ]; then
        warn "Directory $INSTALL_DIR exists but is not a git repo. Backing up and cloning."
        mv "$INSTALL_DIR" "${INSTALL_DIR}.bak.$$"
    fi
    info "Cloning repository (branch: $BRANCH_MAIN)..."
    if ! git clone -b "$BRANCH_MAIN" "$REPO_URL" "$INSTALL_DIR"; then
        err "Clone failed. Check:"
        echo "  - Repo URL is correct and you have access (SSH key or HTTPS token)"
        echo "  - SSH: ssh -T git@github.com   (or git@gitlab.com)"
        echo "  - Network: ping github.com"
        exit 1
    fi
    ok "Repository cloned to $INSTALL_DIR (branch: $BRANCH_MAIN)"
fi

# -----------------------------------------------------------------------------
# Step 4: Python virtual environment and dependencies
# -----------------------------------------------------------------------------

VENV="$INSTALL_DIR/venv"
if [ ! -f "$VENV/bin/activate" ]; then
    info "Creating virtual environment..."
    python3 -m venv "$VENV"
    ok "Virtual environment created."
else
    ok "Virtual environment already exists."
fi

info "Installing Python dependencies..."
"$VENV/bin/pip" install -q --upgrade pip
if [ -f "$INSTALL_DIR/requirements.txt" ]; then
    "$VENV/bin/pip" install -q -r "$INSTALL_DIR/requirements.txt"
    ok "Python dependencies installed."
else
    warn "requirements.txt not found in $INSTALL_DIR; skipping pip install."
fi

# -----------------------------------------------------------------------------
# Step 5: Desktop shortcut, menu entry, and desktop icon
# -----------------------------------------------------------------------------
DESKTOP_DIR="$HOME/.local/share/applications"
mkdir -p "$DESKTOP_DIR"
DESKTOP_FILE="$DESKTOP_DIR/iot-pubsub-gui.desktop"

# Launcher script: must be in repo so it survives in-app update (git clean -fd removes untracked files)
LAUNCHER="$INSTALL_DIR/iot-pubsub-gui-launch.sh"
if [ ! -f "$LAUNCHER" ]; then
    cat > "$LAUNCHER" << 'LAUNCHER_EOF'
#!/bin/bash
cd "$(dirname "$(readlink -f "$0")")"
exec ./venv/bin/python3 iot_pubsub_gui.py "$@"
LAUNCHER_EOF
    ok "Launcher script created: $LAUNCHER"
fi
chmod +x "$LAUNCHER"
sed -i 's/\r$//' "$LAUNCHER" 2>/dev/null || true
ok "Launcher script ready: $LAUNCHER"

# Use custom icon if present in repo (PNG or SVG), otherwise system generic
if [ -f "$INSTALL_DIR/iot-pubsub-gui.png" ]; then
    ICON_LINE="Icon=$INSTALL_DIR/iot-pubsub-gui.png"
elif [ -f "$INSTALL_DIR/iot-pubsub-gui.svg" ]; then
    ICON_LINE="Icon=$INSTALL_DIR/iot-pubsub-gui.svg"
else
    ICON_LINE="Icon=application-x-executable"
fi

# Exec is a single path so the desktop runs immediately without confirmation
cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$APP_NAME
Comment=AWS IoT Pub/Sub GUI for Raspberry Pi
Exec=$LAUNCHER
Path=$INSTALL_DIR
$ICON_LINE
Terminal=false
Categories=Network;Utility;
StartupNotify=true
Keywords=IoT;AWS;MQTT;PubSub;
EOF
# Ensure Unix line endings (avoids "invalid desktop entry" on Pi if repo had CRLF)
sed -i 's/\r$//' "$DESKTOP_FILE" 2>/dev/null || true
ok "Desktop/menu entry created: $DESKTOP_FILE"

# Mark as trusted so it launches without "This file seems to be an executable script" confirmation
if command -v gio &>/dev/null; then
    gio set "$DESKTOP_FILE" metadata::trusted true 2>/dev/null && ok "Launcher marked trusted" || true
fi

# One-time helper: at next graphical login, set trust on Desktop copy (fixes SSH installs). Runs once then removes itself.
# Store outside install dir so in-app update (git clean) does not remove it.
TRUST_ONCE_DIR="$HOME/.local/share/iot-pubsub-gui"
mkdir -p "$TRUST_ONCE_DIR"
TRUST_ONCE_SCRIPT="$TRUST_ONCE_DIR/set-desktop-trust-once.sh"
TRUST_ONCE_AUTOSTART="$HOME/.config/autostart/iot-pubsub-gui-trust-once.desktop"
cat > "$TRUST_ONCE_SCRIPT" << 'TRUSTSCRIPT'
#!/bin/bash
sleep 3
gio set "$HOME/.local/share/applications/iot-pubsub-gui.desktop" metadata::trusted true 2>/dev/null
gio set "$HOME/Desktop/iot-pubsub-gui.desktop" metadata::trusted true 2>/dev/null
rm -f "$HOME/.config/autostart/iot-pubsub-gui-trust-once.desktop"
TRUSTSCRIPT
chmod +x "$TRUST_ONCE_SCRIPT"
sed -i 's/\r$//' "$TRUST_ONCE_SCRIPT" 2>/dev/null || true
mkdir -p "$HOME/.config/autostart"
cat > "$TRUST_ONCE_AUTOSTART" << EOF
[Desktop Entry]
Type=Application
Name=IoT PubSub GUI - Trust desktop icon (once)
Exec=$TRUST_ONCE_SCRIPT
Terminal=false
X-GNOME-Autostart-enabled=true
Hidden=true
EOF
sed -i 's/\r$//' "$TRUST_ONCE_AUTOSTART" 2>/dev/null || true
ok "One-time trust helper added (runs at next login so desktop icon runs without confirmation)"

# Copy (not symlink) to Desktop so Pi desktop accepts it; symlinks can cause "invalid desktop entry file"
DESKTOP_ICON="$HOME/Desktop/iot-pubsub-gui.desktop"
if [ -d "$HOME/Desktop" ]; then
    cp "$DESKTOP_FILE" "$DESKTOP_ICON"
    chmod +x "$DESKTOP_ICON"
    sed -i 's/\r$//' "$DESKTOP_ICON" 2>/dev/null || true
    if command -v gio &>/dev/null; then
        gio set "$DESKTOP_ICON" metadata::trusted true 2>/dev/null && ok "Desktop icon trusted" || true
    fi
    ok "Desktop icon created: $DESKTOP_ICON (click to run)"
else
    warn "Desktop folder not found; skipping desktop icon. Menu shortcut still available."
fi

if command -v update-desktop-database &>/dev/null; then
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
fi

# -----------------------------------------------------------------------------
# Step 6: Optional autostart on boot
# -----------------------------------------------------------------------------
AUTOSTART_DIR="$HOME/.config/autostart"
mkdir -p "$AUTOSTART_DIR"
AUTOSTART_FILE="$AUTOSTART_DIR/iot-pubsub-gui.desktop"

# Only add autostart if user has not disabled it (idempotent: don't overwrite if they removed it)
if [ ! -f "$AUTOSTART_FILE" ]; then
    read -p "Start $APP_NAME on login? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cp "$DESKTOP_FILE" "$AUTOSTART_FILE"
        ok "Autostart enabled. To disable: remove $AUTOSTART_FILE"
    else
        info "Autostart skipped. You can add it later by copying $DESKTOP_FILE to $AUTOSTART_DIR"
    fi
else
    ok "Autostart entry already present."
fi

# -----------------------------------------------------------------------------
# Final instructions
# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  Installation complete"
echo "=============================================="
echo ""
echo "  To run $APP_NAME:"
echo "    • From desktop: click 'IoT PubSub GUI' (after next login it runs without confirmation)"
echo "    • From menu: look for '$APP_NAME' in your applications menu"
echo "    • From terminal:"
echo "        cd $INSTALL_DIR"
echo "        $VENV/bin/python3 iot_pubsub_gui.py"
echo ""
echo "  Place your AWS IoT certificate files in: $INSTALL_DIR"
echo "  Log file: $INSTALL_DIR/iot_pubsub_gui.log"
echo ""

# Optional: show GUI popup if possible (zenity on Raspberry Pi OS)
if command -v zenity &>/dev/null; then
    zenity --info --title="$APP_NAME" --width=400 --text="Installation complete.\n\nRun '$APP_NAME' from your application menu or:\ncd $INSTALL_DIR && $VENV/bin/python3 iot_pubsub_gui.py" 2>/dev/null || true
fi

exit 0
