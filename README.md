# IoT PubSub GUI

AWS IoT Pub/Sub GUI Application using PyQt6 and AWS IoT Device SDK v2. Designed for Raspberry Pi with fullscreen-by-default, in-app self-updating, and a one-click installer.

## Quick Start – One-Click Install (Raspberry Pi)

Use **install.sh** for a brand-new Raspberry Pi (idempotent; safe to run multiple times).

1. Download and run the installer:
   ```bash
   wget https://raw.githubusercontent.com/yourusername/iot-project/main/install.sh
   chmod +x install.sh
   bash install.sh
   ```
   Replace `yourusername/iot-project` with your actual GitHub repo if you use a different URL.

2. The script will:
   - Install required system packages (git, Python 3, venv, pip, build tools, SQLite, optional Qt/OpenGL for GUI)
   - Verify git access to the repo (fails with clear instructions if credentials are missing)
   - Clone the repository (or update it if already present)
   - Create a virtual environment and install Python dependencies from `requirements.txt`
   - Create a desktop icon and menu shortcut
   - Optionally enable auto-start on login

3. Launch the app:
   - From the application menu: **IoT PubSub GUI**, or
   - From terminal: `cd ~/iot-pubsub-gui && venv/bin/python3 iot_pubsub_gui.py`

**Custom install directory or repo URL:**
```bash
IOT_INSTALL_DIR=$HOME/my-iot-app IOT_REPO_URL=https://github.com/you/your-repo.git bash install.sh
```

**Private repo (full credentials required on fresh Pi):**  
The installer verifies git access before cloning. For a **private** repository you must set up credentials first:

- **SSH (recommended):** Generate a key on the Pi (`ssh-keygen -t ed25519 -C "pi@iot"`), add the public key to GitHub/GitLab, then run with an SSH URL:
  ```bash
  IOT_REPO_URL="git@github.com:USER/REPO.git" bash install.sh
  ```
  Test SSH first: `ssh -T git@github.com`
- **HTTPS:** Use a Personal Access Token as the password when git prompts you, or run `git config --global credential.helper store` once, then run the installer.

If the script reports "Cannot access repository", fix SSH/HTTPS access and run it again.

**See [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for more options (standalone installer, git-based installer).**

## Features

- **MQTT Pub/Sub**: Publish and subscribe to AWS IoT Core topics
- **Real-time Message Log**: View received messages in real-time
- **SQLite Database**: All messages are stored in a local database
- **In-app self-update**: Check and apply updates via GitPython (no separate update script); progress dialog and cancel support
- **Fullscreen by default**: Kiosk-style on Raspberry Pi; "Exit fullscreen" button to minimize
- **One-click installer**: `install.sh` for new Raspberry Pi devices

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
├── iot_pubsub_gui.py          # Main application (PyQt6; includes in-app update + fullscreen)
├── requirements.txt           # Python dependencies (includes GitPython)
├── VERSION                    # Version file
├── install.sh                 # One-click installer for new Raspberry Pi
├── install-iot-pubsub-gui.sh  # Alternative git-based installer
├── iot-pubsub-gui.desktop     # Desktop launcher (created by install.sh)
├── venv/                      # Virtual environment (created by installer)
├── .git/                      # Git repository (for in-app updates)
├── *.pem                      # AWS IoT certificates
└── iot_messages.db            # SQLite database (created at runtime)
```

## In-App Self-Update

The application checks for updates on startup (Release/* branches). If a newer version is available, a link appears in the top bar.

**How it works:**
- Uses **GitPython** inside the app for in-app updates.
- Update runs in a **background thread**; the GUI stays responsive.
- A **progress dialog** shows status (e.g. "Fetching...", "Applying updates...") with an indeterminate progress bar and a **Cancel** button.
- When done, you see a message: **"Restart the application to apply changes"** (restart is not forced).
- Handles dirty working tree, no internet, and permission errors with clear messages.

**Requirements:** GitPython (`pip install gitpython`), git installed on the system, and the install directory must be a git clone.

**Manual update (without using the in-app button):**
```bash
cd ~/iot-pubsub-gui
git fetch origin && git pull  # or checkout a specific Release/X branch
venv/bin/pip install -r requirements.txt --upgrade
# Restart the application
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

### install.sh: `$'\r': command not found` or `syntax error near unexpected token`
- The script has Windows line endings (CRLF). On the Pi, fix it once:  
  `sed -i 's/\r$//' install.sh`  
  Then run `bash install.sh` again. The repo uses `.gitattributes` so `*.sh` are stored with LF; if you copied the file from Windows, the `sed` command fixes it.

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
