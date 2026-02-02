# IoT PubSub GUI - Deployment Guide

This guide explains how to deploy the IoT PubSub GUI application to a new Raspberry Pi and how users can upgrade to newer versions.

## Deployment Scenarios

### Scenario 1: First-Time Deployment on New Raspberry Pi (v1.0.0)

**Use Case:** Deploying to a brand new Raspberry Pi that doesn't have git access or SSH keys configured.

**Solution:** Use the **Standalone Installer** - a single self-contained file that packages all application files.

#### Steps:

1. **Download the standalone installer** to your development machine:
   ```bash
   # On your development machine (not the Pi)
   wget https://raw.githubusercontent.com/thienanlktl/Pideployment/main/install-iot-pubsub-gui-standalone.sh
   ```

2. **Transfer the installer to the Raspberry Pi**:
   ```bash
   # Option A: Using SCP (from your development machine)
   scp install-iot-pubsub-gui-standalone.sh pi@<raspberry-pi-ip>:/home/pi/
   
   # Option B: Using USB drive
   # Copy the file to a USB drive, plug into Pi, then copy to home directory
   
   # Option C: Using wget directly on the Pi (if Pi has internet)
   # On the Pi:
   wget https://raw.githubusercontent.com/thienanlktl/Pideployment/main/install-iot-pubsub-gui-standalone.sh
   ```

3. **Run the installer on the Raspberry Pi**:
   ```bash
   # SSH into the Pi or use terminal directly
   cd ~
   chmod +x install-iot-pubsub-gui-standalone.sh
   bash install-iot-pubsub-gui-standalone.sh
   ```

4. **What the installer does**:
   - Updates system packages
   - Installs required dependencies (Python, PyQt6, SQLite3, etc.)
   - Extracts all application files to `~/iot-pubsub-gui/`
   - Creates a Python virtual environment
   - Installs Python dependencies
   - Initializes a git repository (for future auto-updates)
   - Creates a desktop launcher icon
   - Verifies installation

5. **Add certificate files** (if not included in installer):
   ```bash
   # Copy your AWS IoT certificates to:
   cd ~/iot-pubsub-gui
   # Place these files:
   # - AmazonRootCA1.pem
   # - ebb0b9fb27d1eb1ca52f7f89260e123a992759bf3b630f9863575015132ebbef-certificate.pem.crt
   # - ebb0b9fb27d1eb1ca52f7f89260e123a992759bf3b630f9863575015132ebbef-private.pem.key
   ```

6. **Launch the application**:
   - Double-click the "IoT PubSub GUI" icon on the desktop, OR
   - Run from terminal:
     ```bash
     cd ~/iot-pubsub-gui
     source venv/bin/activate
     python3 iot_pubsub_gui.py
     ```

---

### Scenario 2: Deployment with Git Access

**Use Case:** Raspberry Pi has internet access and git is available.

**Solution:** Use the **Git-based Installer** - clones the repository directly from GitHub.

#### Steps:

1. **Download and run the git-based installer**:
   ```bash
   # On the Raspberry Pi
   wget https://raw.githubusercontent.com/thienanlktl/Pideployment/main/install-iot-pubsub-gui.sh
   chmod +x install-iot-pubsub-gui.sh
   bash install-iot-pubsub-gui.sh
   ```

2. **What the installer does**:
   - Updates system packages
   - Installs required dependencies
   - Clones repository from GitHub to `~/iot-pubsub-gui/`
   - Creates virtual environment
   - Installs Python dependencies
   - Creates desktop launcher
   - Sets up git repository (already done via clone)

3. **Add certificate files** (same as Scenario 1)

4. **Launch the application** (same as Scenario 1)

---

## Upgrading the Application

### Automatic Upgrade (Recommended)

The application automatically checks for updates on startup. If a newer version is available:

1. **Notification appears** in the top-right corner of the GUI: "New update available!"
2. **Click "Update Now"** button
3. **Confirm the update** in the dialog
4. **Application will**:
   - Fetch latest code from GitHub
   - Update all files
   - Upgrade Python dependencies
   - Restart automatically

**Requirements for auto-update:**
- Git must be installed on the Pi
- Installation directory must be a git repository (automatically set up by both installers)
- Internet connection must be available
- GitHub repository must be accessible

### Manual Upgrade

If auto-update doesn't work, you can manually upgrade:

```bash
cd ~/iot-pubsub-gui

# Activate virtual environment
source venv/bin/activate

# Update code
git fetch origin
git reset --hard origin/main

# Update dependencies
pip install -r requirements.txt --upgrade

# Restart the application
python3 iot_pubsub_gui.py
```

### Re-running the Installer

You can also re-run the installer to update:

```bash
# For git-based installer
bash install-iot-pubsub-gui.sh

# For standalone installer (will extract new version)
bash install-iot-pubsub-gui-standalone.sh
```

**Note:** Re-running the standalone installer will overwrite existing files. Make sure to backup any custom configurations first.

---

## Version Management

### Current Version

The application version is stored in the `VERSION` file in the installation directory:
```bash
cat ~/iot-pubsub-gui/VERSION
```

The version is also displayed in the GUI (top-left corner).

### Version History

- **v1.0.0**: Initial release with standalone installer support

---

## Troubleshooting

### Auto-update doesn't work

**Problem:** Update notification doesn't appear or update fails.

**Solutions:**
1. Check if git is installed: `git --version`
2. Check if installation directory is a git repository: `cd ~/iot-pubsub-gui && git status`
3. If not a git repo, initialize it:
   ```bash
   cd ~/iot-pubsub-gui
   git init
   git remote add origin https://github.com/thienanlktl/Pideployment.git
   git add .
   git commit -m "Initial commit"
   git branch -M main
   ```
4. Check internet connectivity: `ping github.com`
5. Check GitHub API access: `curl https://api.github.com/repos/thienanlktl/Pideployment/commits/main`

### Standalone installer fails

**Problem:** Installer script fails during execution.

**Solutions:**
1. Check if running on Raspberry Pi OS (Debian-based Linux)
2. Ensure you're not running as root (script will ask for sudo when needed)
3. Check disk space: `df -h`
4. Check internet connectivity for package downloads
5. Review error messages in the installer output

### Application won't start after update

**Problem:** Application crashes or won't launch after updating.

**Solutions:**
1. Check Python dependencies: `pip list`
2. Reinstall dependencies: `pip install -r requirements.txt --upgrade`
3. Check for errors in log file: `cat ~/iot-pubsub-gui/iot_pubsub_gui.log`
4. Verify certificate files are still present
5. Try manual restart: `cd ~/iot-pubsub-gui && source venv/bin/activate && python3 iot_pubsub_gui.py`

---

## Best Practices

1. **Always backup certificate files** before updating
2. **Test updates on a non-production Pi first** if possible
3. **Keep the standalone installer** as a backup for quick reinstallation
4. **Monitor the application log** after updates: `tail -f ~/iot-pubsub-gui/iot_pubsub_gui.log`
5. **Document any custom configurations** before updating

---

## Summary

- **First-time deployment on new Pi**: Use `install-iot-pubsub-gui-standalone.sh`
- **Deployment with git access**: Use `install-iot-pubsub-gui.sh`
- **Future upgrades**: Use the built-in auto-update feature in the GUI
- **Manual upgrades**: Use git commands or re-run installer

Both installers set up the installation directory as a git repository, enabling automatic updates after the initial installation.
