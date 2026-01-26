# Complete Setup Guide - Fully Automated

## Overview

The `setup-deployment-from-scratch.sh` script automates **everything**:

1. ✅ **Clone repository** - Automatically clones from GitHub
2. ✅ **Install dependencies** - System packages and Python packages
3. ✅ **Run Python application** - Starts `iot_pubsub_gui.py` automatically
4. ✅ **Setup ngrok** - Uses pre-configured token automatically
5. ✅ **Create GitHub webhook** - Automatically creates webhook (if token provided)
6. ✅ **Receive POST calls** - Webhook listener ready to trigger updates

## Quick Start

### Option 1: Fully Automated (Recommended)

```bash
# Set your GitHub token (one-time)
export GITHUB_TOKEN="your_github_token"

# Run setup (everything automated!)
./setup-deployment-from-scratch.sh
```

The script will:
- Clone repo automatically
- Install all dependencies
- Start the Python app
- Setup ngrok with pre-configured token
- Create GitHub webhook (if token provided)

### Option 2: With Pre-configured Tokens

Create a file `.env` (or set environment variables):

```bash
export NGROK_AUTHTOKEN="38HbghqIwfeBRpp4wdZHFkeTOT1_2Dh6671w4NZEUoFMpcVa6"
export GITHUB_TOKEN="your_github_token"
```

Then run:
```bash
source .env
./setup-deployment-from-scratch.sh
```

## What Gets Automated

### 1. Repository Cloning
- Detects if repo exists
- Clones from `https://github.com/thienanlktl/Pideployment`
- Uses SSH if key available, otherwise HTTPS
- Handles existing SSH keys in current directory

### 2. Dependencies Installation
- **System packages**: Python3, git, build tools, PyQt6 system libs
- **Python packages**: PyQt6, awsiotsdk, Flask, and all from `requirements.txt`
- Creates and activates virtual environment
- Upgrades pip automatically

### 3. Python Application
- Starts `iot_pubsub_gui.py` automatically
- Runs in background with proper logging
- Saves PID for process management
- Handles DISPLAY environment for GUI

### 4. ngrok Setup
- Uses pre-configured token: `38HbghqIwfeBRpp4wdZHFkeTOT1_2Dh6671w4NZEUoFMpcVa6`
- Installs ngrok if needed
- Configures authtoken
- Creates systemd service
- Starts tunnel automatically
- Gets public URL

### 5. GitHub Webhook Creation
- Automatically creates webhook via GitHub API
- Uses webhook URL from ngrok
- Uses secret from `.webhook_secret`
- Updates existing webhook if found
- Requires `GITHUB_TOKEN` environment variable

### 6. Webhook Listener
- Installs systemd service
- Starts automatically
- Listens on port 9000
- Receives GitHub POST calls
- Triggers `update-and-restart.sh` on push

## Manual Steps (If Needed)

### If GitHub Token Not Provided

1. **Get GitHub Token:**
   - Go to: https://github.com/settings/tokens
   - Click "Generate new token (classic)"
   - Select scope: `repo` (for private) or `public_repo` (for public)
   - Copy token

2. **Create Webhook:**
   ```bash
   export GITHUB_TOKEN="your_token"
   ./create-github-webhook.sh
   ```

### If SSH Key Not Added to GitHub

1. **Get Public Key:**
   ```bash
   cat ~/.ssh/id_ed25519_iot_gui.pub
   ```

2. **Add to GitHub:**
   - Go to: https://github.com/thienanlktl/Pideployment/settings/keys
   - Click "Add deploy key"
   - Paste public key
   - Click "Add key"

## Testing the Complete Flow

### 1. Test Webhook Endpoint
```bash
# Local health check
curl http://localhost:9000/health

# Get public URL
./get-ngrok-url.sh
```

### 2. Test Webhook Trigger
1. Make a small change to your repo
2. Commit and push to `main` branch
3. Watch webhook logs:
   ```bash
   sudo journalctl -u iot-gui-webhook.service -f
   ```
4. Check app restarts automatically

### 3. Test Manual Update
```bash
./update-and-restart.sh
```

## Verification Checklist

After running setup, verify:

- [ ] Repository cloned: `ls ~/Pideployment`
- [ ] Virtual environment: `ls venv/bin/python`
- [ ] Python app running: `pgrep -f iot_pubsub_gui.py`
- [ ] ngrok running: `sudo systemctl status iot-gui-ngrok.service`
- [ ] Webhook service: `sudo systemctl status iot-gui-webhook.service`
- [ ] Webhook URL: `./get-ngrok-url.sh`
- [ ] GitHub webhook: https://github.com/thienanlktl/Pideployment/settings/hooks

## Troubleshooting

### App Not Starting
```bash
# Check logs
tail -f logs/app.log

# Check dependencies
source venv/bin/activate
python -c "import PyQt6; import awsiot"
```

### ngrok Not Working
```bash
# Check service
sudo systemctl status iot-gui-ngrok.service

# View logs
sudo journalctl -u iot-gui-ngrok.service -f

# Restart
sudo systemctl restart iot-gui-ngrok.service
```

### Webhook Not Receiving Events
```bash
# Check webhook service
sudo systemctl status iot-gui-webhook.service

# View logs
sudo journalctl -u iot-gui-webhook.service -f

# Check GitHub webhook delivery
# Go to: https://github.com/thienanlktl/Pideployment/settings/hooks
# Click on webhook → Recent Deliveries
```

## Summary

With `setup-deployment-from-scratch.sh`, you get:

✅ **One command setup** - Everything automated  
✅ **No router config** - ngrok handles it  
✅ **Auto webhook** - Creates GitHub webhook automatically  
✅ **Auto app start** - Python app runs immediately  
✅ **Auto updates** - Push to GitHub triggers restart  

Just run: `./setup-deployment-from-scratch.sh` 🚀

