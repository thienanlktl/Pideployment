#!/bin/bash
# Ensure virtual environment exists and all packages from requirements.txt are installed.
# Safe to run multiple times (idempotent). Use from install, kiosk autostart, or manually.
# Usage: ./ensure_venv.sh [APP_DIR]
#   APP_DIR defaults to directory containing this script.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${1:-$SCRIPT_DIR}"
cd "$APP_DIR" || { echo "ERROR: Cannot cd to $APP_DIR"; exit 1; }

VENV="$APP_DIR/venv"
REQ="$APP_DIR/requirements.txt"
PYTHON="${VENV}/bin/python3"
PIP="${VENV}/bin/pip"

# Create venv if missing
if [ ! -f "$PYTHON" ]; then
    echo "[ensure_venv] Creating virtual environment in $VENV ..."
    python3 -m venv "$VENV"
    echo "[ensure_venv] Virtual environment created."
else
    echo "[ensure_venv] Virtual environment already exists."
fi

# Upgrade pip
"$PIP" install -q --upgrade pip

# Install all packages from requirements.txt
if [ -f "$REQ" ]; then
    echo "[ensure_venv] Installing packages from requirements.txt ..."
    "$PIP" install -r "$REQ"
    echo "[ensure_venv] Packages installed."
else
    echo "[ensure_venv] WARNING: requirements.txt not found at $REQ"
    exit 1
fi

# Verify critical imports (map package name -> import name)
verify_import() {
    local import_name="$1"
    if "$PYTHON" -c "import $import_name" 2>/dev/null; then
        echo "[ensure_venv] OK: $import_name"
        return 0
    else
        echo "[ensure_venv] FAIL: cannot import $import_name"
        return 1
    fi
}

echo "[ensure_venv] Verifying imports ..."
FAIL=0
verify_import "PyQt6"       || FAIL=1
verify_import "awscrt"      || FAIL=1
verify_import "awsiot"      || FAIL=1
verify_import "cryptography" || FAIL=1
verify_import "dateutil"    || FAIL=1
verify_import "requests"    || FAIL=1
verify_import "git"         || FAIL=1

if [ "$FAIL" -eq 1 ]; then
    echo "[ensure_venv] ERROR: Some packages failed to import. Run: $PIP install -r $REQ"
    exit 1
fi

echo "[ensure_venv] All packages installed and verified. Use: $PYTHON iot_pubsub_gui.py"
