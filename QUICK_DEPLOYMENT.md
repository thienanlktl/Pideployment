# Quick Deployment Reference

## First-Time Deployment on New Raspberry Pi

### Step 1: Get the Standalone Installer

**Option A: Download directly on Pi (if Pi has internet)**
```bash
wget https://raw.githubusercontent.com/thienanlktl/Pideployment/main/install-iot-pubsub-gui-standalone.sh
chmod +x install-iot-pubsub-gui-standalone.sh
```

**Option B: Transfer from another computer**
```bash
# On your computer:
scp install-iot-pubsub-gui-standalone.sh pi@<pi-ip-address>:/home/pi/
```

### Step 2: Run the Installer
```bash
bash install-iot-pubsub-gui-standalone.sh
```

**What it does:**
- ✅ Updates system packages
- ✅ Installs dependencies (Python, PyQt6, SQLite3, Git, etc.)
- ✅ Extracts all application files
- ✅ Creates virtual environment
- ✅ Installs Python packages
- ✅ Sets up git repository (for future auto-updates)
- ✅ Creates desktop launcher

### Step 3: Add Certificate Files
```bash
cd ~/iot-pubsub-gui
# Copy your AWS IoT certificates here:
# - AmazonRootCA1.pem
# - ebb0b9fb27d1eb1ca52f7f89260e123a992759bf3b630f9863575015132ebbef-certificate.pem.crt
# - ebb0b9fb27d1eb1ca52f7f89260e123a992759bf3b630f9863575015132ebbef-private.pem.key
```

### Step 4: Launch Application
- **Double-click** the "IoT PubSub GUI" icon on desktop, OR
- **Terminal:**
  ```bash
  cd ~/iot-pubsub-gui
  source venv/bin/activate
  python3 iot_pubsub_gui.py
  ```

---

## Upgrading to New Version

### Automatic (Recommended)
1. Launch the application
2. If update available → notification appears in top-right
3. Click **"Update Now"**
4. Confirm → app updates and restarts automatically

### Manual
```bash
cd ~/iot-pubsub-gui
source venv/bin/activate
git fetch origin
git reset --hard origin/main
pip install -r requirements.txt --upgrade
python3 iot_pubsub_gui.py
```

---

## Installation Locations

- **Application:** `~/iot-pubsub-gui/`
- **Desktop Launcher:** `~/Desktop/iot-pubsub-gui.desktop`
- **Database:** `~/iot-pubsub-gui/iot_messages.db`
- **Log File:** `~/iot-pubsub-gui/iot_pubsub_gui.log`

---

## Quick Troubleshooting

| Problem | Solution |
|---------|----------|
| Installer fails | Check internet, disk space, run as non-root user |
| App won't start | Check `iot_pubsub_gui.log` for errors |
| Can't connect to AWS IoT | Verify certificate files are in `~/iot-pubsub-gui/` |
| Auto-update doesn't work | Run `cd ~/iot-pubsub-gui && git status` to verify git repo |
| Dependencies missing | Run `pip install -r requirements.txt --upgrade` |

---

## Full Documentation

See [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for detailed instructions.

