# Setup from Scratch - Complete Guide

## Overview

The `setup-deployment-from-scratch.sh` script automates the entire deployment setup process on your Raspberry Pi. It handles everything from installing dependencies to configuring services.

## What It Does

The script performs these steps automatically:

1. ✅ **Checks Prerequisites** - Verifies Python 3, git, and other tools
2. ✅ **Installs System Dependencies** - Installs required packages (python3-dev, build tools, Qt libraries)
3. ✅ **Sets Up Virtual Environment** - Creates and configures Python virtual environment
4. ✅ **Installs Python Dependencies** - Installs Flask, PyQt6, AWS IoT SDK, and other packages
5. ✅ **Generates SSH Key** - Creates ed25519 key pair for GitHub authentication
6. ✅ **Configures Git** - Sets up git remote URL for your repository
7. ✅ **Generates Webhook Secret** - Creates secure secret for webhook verification
8. ✅ **Makes Scripts Executable** - Sets proper permissions on all scripts
9. ✅ **Configures Systemd Service** - Installs and enables webhook listener service
10. ✅ **Configures Firewall** - Opens webhook port if UFW is installed
11. ✅ **Tests Setup** - Runs verification tests
12. ✅ **Provides Summary** - Shows next steps and configuration details

## Usage

### Basic Usage

```bash
cd ~/PublishDemo
chmod +x setup-deployment-from-scratch.sh
./setup-deployment-from-scratch.sh
```

### Custom Configuration

You can customize the setup by setting environment variables:

```bash
# Custom GitHub username and repository
export GITHUB_USER="your-username"
export REPO_NAME="your-repo-name"
export GIT_BRANCH="main"
export WEBHOOK_PORT="9000"

./setup-deployment-from-scratch.sh
```

Or run with inline variables:

```bash
GITHUB_USER="your-username" REPO_NAME="your-repo" ./setup-deployment-from-scratch.sh
```

## Interactive Steps

The script will pause at these points for your input:

### 1. SSH Key Generation
- If a key already exists, you'll be asked if you want to generate a new one
- The public key will be displayed - **copy it** for GitHub

### 2. Adding SSH Key to GitHub
- The script will display your public key
- It will pause so you can add it to GitHub
- Go to: `https://github.com/thienanlktl/Pideployment/settings/keys`
- Click "Add deploy key" and paste the key

### 3. Git Remote Configuration
- If a git remote exists, you'll be asked if you want to update it
- Choose between standard SSH URL or SSH alias format

### 4. Webhook Secret
- The script generates a secure secret
- **Copy it** - you'll need it for GitHub webhook setup
- The secret is also saved to `.webhook_secret` file

### 5. Systemd Service
- You'll be asked if you want to start the service immediately
- Choose "y" to start it now, or "n" to start it later

### 6. Firewall Configuration
- If UFW firewall is active, you'll be asked to open the webhook port
- Choose "y" to allow external access to the webhook

## After Running the Script

### Step 1: Add SSH Key to GitHub

1. The script displayed your public key - copy it
2. Go to: `https://github.com/thienanlktl/Pideployment/settings/keys`
3. Click "Add deploy key"
4. Paste the public key
5. Give it a title (e.g., "Raspberry Pi Deploy Key")
6. Check "Allow write access" only if you need to push changes
7. Click "Add key"

### Step 2: Add Webhook to GitHub

1. The script displayed your webhook secret - copy it
2. Go to: `https://github.com/thienanlktl/Pideployment/settings/hooks`
3. Click "Add webhook"
4. Fill in:
   - **Payload URL:** `http://YOUR_PI_IP:9000/webhook`
     - Replace `YOUR_PI_IP` with the IP shown by the script
   - **Content type:** `application/json`
   - **Secret:** Paste the secret from the script
   - **Which events:** Select "Just the push event"
   - **Active:** Checked
5. Click "Add webhook"

### Step 3: Verify Everything Works

```bash
# Check webhook service status
sudo systemctl status iot-gui-webhook.service

# Test webhook health endpoint
curl http://localhost:9000/health

# View webhook logs
sudo journalctl -u iot-gui-webhook.service -f

# Test manual update
./update-and-restart.sh
```

## Files Created/Modified

The script creates and configures:

- `~/.ssh/id_ed25519_iot_gui` - SSH private key
- `~/.ssh/id_ed25519_iot_gui.pub` - SSH public key
- `~/.ssh/config` - SSH configuration for GitHub
- `venv/` - Python virtual environment
- `.webhook_secret` - Webhook secret (restricted permissions)
- `/etc/systemd/system/iot-gui-webhook.service` - Systemd service file

## Troubleshooting

### Script Fails at System Dependencies

```bash
# Update package list manually
sudo apt-get update

# Install missing packages
sudo apt-get install -y python3 python3-pip python3-venv git
```

### SSH Key Already Exists

The script will ask if you want to overwrite it. Choose:
- **y** - Generate a new key (old key will stop working)
- **n** - Use existing key

### Git Remote Configuration Fails

```bash
# Manually set git remote
git remote set-url origin git@github.com:YOUR_USERNAME/YOUR_REPO.git

# Test connection
ssh -T git@github.com
```

### Systemd Service Fails to Start

```bash
# Check service status
sudo systemctl status iot-gui-webhook.service

# View detailed logs
sudo journalctl -u iot-gui-webhook.service -n 50

# Check if paths are correct in service file
sudo nano /etc/systemd/system/iot-gui-webhook.service
```

### Webhook Not Accessible

1. **Check firewall:**
   ```bash
   sudo ufw status
   sudo ufw allow 9000/tcp
   ```

2. **Check if service is running:**
   ```bash
   sudo systemctl status iot-gui-webhook.service
   ```

3. **Check if port is listening:**
   ```bash
   sudo netstat -tuln | grep 9000
   # or
   sudo ss -tuln | grep 9000
   ```

4. **Test locally:**
   ```bash
   curl http://localhost:9000/health
   ```

## Re-running the Script

The script is **idempotent** - you can run it multiple times safely:

- ✅ Existing SSH keys won't be overwritten (unless you choose to)
- ✅ Virtual environment won't be recreated (unless missing)
- ✅ Systemd service will be updated with new configuration
- ✅ Scripts will be made executable again

## Manual Steps Not Automated

The script cannot automate these steps (requires GitHub web interface):

1. ❌ Adding SSH key to GitHub (you must do this manually)
2. ❌ Creating GitHub webhook (you must do this manually)

These steps require GitHub authentication and cannot be automated via script.

## Next Steps

After setup is complete:

1. ✅ Add SSH key to GitHub
2. ✅ Add webhook to GitHub
3. ✅ Test by pushing a commit to the main branch
4. ✅ Monitor logs to see automatic update

## Support

If you encounter issues:

1. Check the script output for error messages
2. Review log files:
   - `update.log` - Update script logs
   - `webhook.log` - Webhook listener logs
   - `sudo journalctl -u iot-gui-webhook.service` - Service logs
3. Run the test script:
   ```bash
   ./test-deployment.sh
   ```
4. See `DEPLOYMENT_SETUP.md` for detailed troubleshooting

