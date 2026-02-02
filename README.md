# IoT PubSub GUI

AWS IoT Pub/Sub GUI Application using PyQt6 and AWS IoT Device SDK v2.

## Quick Start

### First-Time Installation on New Raspberry Pi

**For new Raspberry Pi without git access**, use the standalone installer:

1. Download the standalone installer:
   ```bash
   wget https://raw.githubusercontent.com/thienanlktl/Pideployment/main/install-iot-pubsub-gui-standalone.sh
   ```

2. Run the installer:
   ```bash
   chmod +x install-iot-pubsub-gui-standalone.sh
   bash install-iot-pubsub-gui-standalone.sh
   ```

**For Raspberry Pi with git access**, use the git-based installer:

1. Download the installer:
   ```bash
   wget https://raw.githubusercontent.com/thienanlktl/Pideployment/main/install-iot-pubsub-gui.sh
   ```

2. Run the installer:
   ```bash
   chmod +x install-iot-pubsub-gui.sh
   bash install-iot-pubsub-gui.sh
   ```

3. Launch the application:
   - **Desktop Icon**: Double-click the "IoT PubSub GUI" icon on your desktop
   - **Terminal**: 
     ```bash
     cd ~/iot-pubsub-gui
     source venv/bin/activate
     python3 iot_pubsub_gui.py
     ```

**See [HOW_TO_RUN.md](HOW_TO_RUN.md) for detailed instructions on running the application.**

**See [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for detailed deployment instructions.**

## Features

- **MQTT Pub/Sub**: Publish and subscribe to AWS IoT Core topics
- **Real-time Message Log**: View received messages in real-time
- **SQLite Database**: All messages are stored in a local database
- **Auto-Update Check**: Application checks for updates on startup

## Requirements

- Raspberry Pi OS (Debian-based Linux)
- Python 3.8+
- AWS IoT Core certificates (see below)
- Internet connection (for updates)

## Certificate Files

The application requires three certificate files in the installation directory:

1. `AmazonRootCA1.pem` - AWS Root CA certificate
2. `ebb0b9fb27d1eb1ca52f7f89260e123a992759bf3b630f9863575015132ebbef-certificate.pem.crt` - Device certificate
3. `ebb0b9fb27d1eb1ca52f7f89260e123a992759bf3b630f9863575015132ebbef-private.pem.key` - Private key

These files should be placed in `~/iot-pubsub-gui/` directory.

## Project Structure

```
iot-pubsub-gui/
├── iot_pubsub_gui.py          # Main application
├── requirements.txt            # Python dependencies
├── VERSION                     # Version file
├── install-iot-pubsub-gui.sh           # Git-based installer
├── install-iot-pubsub-gui-standalone.sh # Standalone installer (for new Pi)
├── iot-pubsub-gui.desktop      # Desktop launcher
├── venv/                       # Virtual environment (created by installer)
├── .git/                       # Git repository (for auto-updates)
├── *.pem                       # AWS IoT certificates
└── iot_messages.db             # SQLite database (created at runtime)
```

## Auto-Update

The application automatically checks for updates on startup by comparing the local git commit SHA with the latest commit on GitHub. If an update is available, a notification will appear in the top-right corner of the GUI.

**How it works:**
- Both installers automatically set up a git repository in the installation directory
- On startup, the app checks GitHub for newer commits
- If an update is available, click "Update Now" to upgrade
- The app will fetch latest code, update dependencies, and restart automatically

**Requirements:**
- Git must be installed (automatically installed by both installers)
- Internet connection must be available
- Installation directory must be a git repository (automatically configured)

**To update manually:**
```bash
cd ~/iot-pubsub-gui
source venv/bin/activate
git fetch origin
git reset --hard origin/main
pip install -r requirements.txt --upgrade
python3 iot_pubsub_gui.py
```

## Manual Installation

If you prefer to install manually:

```bash
# Clone repository
git clone https://github.com/thienanlktl/Pideployment.git ~/iot-pubsub-gui
cd ~/iot-pubsub-gui

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Run application
python3 iot_pubsub_gui.py
```

## Troubleshooting

### Application won't start
- Ensure you're running on a system with a desktop environment
- Check that all dependencies are installed: `pip list`
- Verify Python version: `python3 --version` (should be 3.8+)

### Cannot connect to AWS IoT
- Verify certificate files are in the correct location
- Check certificate file permissions
- Ensure your device has internet connectivity
- Verify AWS IoT endpoint and thing name are correct

### Update check fails
- Check internet connectivity
- Verify git is installed: `git --version`
- Check that the repository is a valid git repository: `cd ~/iot-pubsub-gui && git status`
- If not a git repo, initialize it (see DEPLOYMENT_GUIDE.md)

## License

This project is provided as-is for educational and development purposes.

## Support

For issues and questions, please open an issue on GitHub.
