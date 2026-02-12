#!/bin/bash
# Kiosk monitor: restart iot_pubsub_gui.py if it exits. Run from labwc autostart.
# Ensures venv and all packages are installed before starting (run ensure_venv.sh if venv missing).
APP_DIR="${APP_DIR:-/home/pi/iot-pubsub-gui}"
PYTHON="${PYTHON:-$APP_DIR/venv/bin/python3}"
SCRIPT="${SCRIPT:-$APP_DIR/iot_pubsub_gui.py}"
CHECK_INTERVAL="${CHECK_INTERVAL:-10}"

cd "$APP_DIR" || exit 1

# Ensure venv exists and all packages installed (idempotent)
if [ ! -f "$PYTHON" ]; then
    if [ -f "$APP_DIR/ensure_venv.sh" ]; then
        bash "$APP_DIR/ensure_venv.sh" "$APP_DIR" || exit 1
    else
        echo "ERROR: venv not found and ensure_venv.sh not in $APP_DIR" >&2
        exit 1
    fi
fi

while true; do
    if ! pgrep -f "python3.*iot_pubsub_gui.py" > /dev/null 2>&1; then
        "$PYTHON" "$SCRIPT" --kiosk &
    fi
    sleep "$CHECK_INTERVAL"
done
