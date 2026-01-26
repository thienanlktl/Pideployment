# AWS IoT Pub/Sub GUI - Setup Instructions for Raspberry Pi

This guide will help you set up and run the AWS IoT Pub/Sub GUI application on your Raspberry Pi with a single click.

## Quick Start (Easiest Method)

### Option 1: Desktop Launcher (Recommended)

1. **Make the script executable:**
   - Right-click on `setup-and-run.sh` in the file manager
   - Select "Properties" → "Permissions" tab
   - Check "Execute" or "Allow executing file as program"
   - Click "OK"
   
   OR use terminal:
   ```bash
   chmod +x setup-and-run.sh
   ```

2. **Set up the desktop launcher:**
   
   **Easy method (recommended):**
   ```bash
   chmod +x create-desktop-launcher.sh
   ./create-desktop-launcher.sh
   ```
   This will automatically create a desktop launcher with the correct path.
   
   **Manual method:**
   - Copy `iot-pubsub-gui.desktop` to your Desktop:
     ```bash
     cp iot-pubsub-gui.desktop ~/Desktop/
     ```
   
   - Edit the desktop file to set the correct path:
     ```bash
     nano ~/Desktop/iot-pubsub-gui.desktop
     ```
     Replace `/path/to/PublishDemo` with your actual project path (e.g., `/home/pi/PublishDemo`)
   
   - Make it executable:
     ```bash
     chmod +x ~/Desktop/iot-pubsub-gui.desktop
     ```
   
   - Right-click the desktop icon → "Properties" → "Permissions"
   - Check "Allow executing file as program"

3. **Double-click the desktop icon** to launch the application!

### Option 2: Direct Script Execution

1. **Make the script executable:**
   ```bash
   chmod +x setup-and-run.sh
   ```

2. **Run the script:**
   ```bash
   ./setup-and-run.sh
   ```
   
   OR simply double-click `setup-and-run.sh` in the file manager (after making it executable).

## What the Script Does

The `setup-and-run.sh` script automatically:

1. ✅ Checks if Python 3 is installed
2. ✅ Installs system dependencies (if needed, with your permission)
3. ✅ Creates a virtual environment (if it doesn't exist)
4. ✅ Upgrades pip to the latest version
5. ✅ Installs PyQt6 (may take 30-60 minutes on first run if building from source)
6. ✅ Installs AWS IoT SDK (awsiotsdk)
7. ✅ Verifies all dependencies are installed
8. ✅ Launches the application

**Note:** The script is **idempotent** - you can run it multiple times safely. It will skip steps that are already completed.

## Prerequisites

### Required:
- Raspberry Pi running Raspberry Pi OS (Debian-based)
- Python 3.8 or higher (usually pre-installed)
- Internet connection (for downloading packages)

### Optional but Recommended:
- Desktop environment (for GUI)
- Certificate files in the project folder:
  - `AmazonRootCA1.pem`
  - `ebb0b9fb27d1eb1ca52f7f89260e123a992759bf3b630f9863575015132ebbef-certificate.pem.crt`
  - `ebb0b9fb27d1eb1ca52f7f89260e123a992759bf3b630f9863575015132ebbef-private.pem.key`

## First-Time Setup

On the **first run**, the script will:

1. Ask for permission to install system packages (requires sudo password)
2. Create a virtual environment in the `venv` folder
3. Download and install PyQt6 (this may take 30-60 minutes on Raspberry Pi)
4. Download and install AWS IoT SDK
5. Launch the application

**Subsequent runs** will be much faster (usually under 10 seconds) as dependencies are already installed.

## Troubleshooting

### Issue: "Permission denied" when running the script

**Solution:**
```bash
chmod +x setup-and-run.sh
```

### Issue: PyQt6 installation fails

**Solution:** Install system dependencies manually:
```bash
sudo apt-get update
sudo apt-get install -y python3-dev build-essential \
    libxcb-xinerama0 libxkbcommon-x11-0 \
    libqt6gui6 libqt6widgets6 libqt6core6
```

Then run the script again:
```bash
./setup-and-run.sh
```

### Issue: Application doesn't start (no window appears)

**Possible causes:**
1. **Running via SSH without X11 forwarding:**
   - Use: `ssh -X pi@raspberrypi-ip`
   - Or run directly on the Pi (not via SSH)

2. **DISPLAY not set:**
   - If on desktop: `export DISPLAY=:0`
   - Then run: `./setup-and-run.sh`

3. **Missing certificate files:**
   - The application will start but won't be able to connect
   - Place certificate files in the project folder

### Issue: "Virtual environment activation failed"

**Solution:**
```bash
sudo apt-get install -y python3-venv
./setup-and-run.sh
```

### Issue: Desktop launcher doesn't work

**Solution 1:** Make it executable and trusted:
```bash
chmod +x ~/Desktop/iot-pubsub-gui.desktop
```

**Solution 2:** Edit the desktop file to use absolute path:
```bash
nano ~/Desktop/iot-pubsub-gui.desktop
```

Change the `Exec` line to:
```
Exec=bash -c "cd '/home/pi/PublishDemo' && ./setup-and-run.sh"
```
(Replace `/home/pi/PublishDemo` with your actual project path)

**Solution 3:** Use the script directly instead of the desktop file:
```bash
./setup-and-run.sh
```

## Manual Installation (Advanced)

If you prefer to install dependencies manually:

1. **Install system packages:**
   ```bash
   sudo apt-get update
   sudo apt-get install -y python3 python3-pip python3-venv \
       python3-dev build-essential \
       libxcb-xinerama0 libxkbcommon-x11-0 \
       libqt6gui6 libqt6widgets6 libqt6core6
   ```

2. **Create virtual environment:**
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   ```

3. **Install Python packages:**
   ```bash
   pip install --upgrade pip
   pip install PyQt6 awsiotsdk
   ```

4. **Run the application:**
   ```bash
   python iot_pubsub_gui.py
   ```

## File Structure

After running the script, your project folder should look like:

```
PublishDemo/
├── setup-and-run.sh          # Main setup and run script
├── iot-pubsub-gui.desktop    # Desktop launcher file
├── iot_pubsub_gui.py         # Main application
├── venv/                     # Virtual environment (created by script)
│   ├── bin/
│   ├── lib/
│   └── ...
├── AmazonRootCA1.pem         # AWS IoT certificate (required)
├── *.pem.crt                 # Device certificate (required)
└── *.pem.key                 # Private key (required)
```

## Notes

- The `venv` folder contains all Python dependencies and can be quite large (several hundred MB)
- You can safely delete the `venv` folder and run the script again to recreate it
- The script will ask for sudo password only if system packages need to be installed
- All Python packages are installed in the virtual environment, not system-wide

## Support

If you encounter issues:

1. Check the error messages in the terminal
2. Verify all prerequisites are met
3. Try running the script again (it's safe to run multiple times)
4. Check that certificate files are in the correct location
5. Ensure you have internet connectivity

## Security Note

The script will ask for your sudo password only when installing system packages. You can decline this and install packages manually if you prefer. The Python packages are installed in the virtual environment and don't require sudo.

