# Automated Deployment Setup Guide

This guide will help you set up automated code updates and application restart when you push changes to your GitHub repository.

## Overview

The deployment system consists of:
1. **SSH Key Setup** - For secure GitHub authentication
2. **Update Script** - Pulls code, updates dependencies, restarts app
3. **Webhook Listener** - Receives GitHub push events and triggers updates
4. **Systemd Service** - Runs webhook listener as a background service
5. **Cron Fallback** - Optional periodic check for updates

## Quick Start: Automated Setup from Scratch (Recommended)

**For a completely automated setup, use the master setup script:**

```bash
cd ~/PublishDemo
chmod +x setup-deployment-from-scratch.sh
./setup-deployment-from-scratch.sh
```

This script will:
- ✅ Install all system dependencies
- ✅ Set up virtual environment
- ✅ Install Python packages (including Flask)
- ✅ Generate SSH key for GitHub
- ✅ Configure git repository
- ✅ Generate webhook secret
- ✅ Set up systemd service
- ✅ Configure firewall
- ✅ Test the setup

**The script will guide you through:**
1. Adding the SSH public key to GitHub
2. Configuring the GitHub webhook

**After running the script, you only need to:**
1. Add the SSH public key to GitHub (script will display it)
2. Add the webhook to GitHub (script will provide the URL and secret)

Then you're done! The system will automatically update when you push to GitHub.

---

## Manual Setup (Alternative Method)

If you prefer to set up components individually, follow the steps below.

## Prerequisites

- Raspberry Pi running Raspberry Pi OS
- Git repository already cloned to `~/PublishDemo` (or your project directory)
- GitHub repository: `git@github.com:thienanlktl/Pideployment.git` or `https://github.com/thienanlktl/Pideployment.git`
- Python 3 and virtual environment setup (from `setup-and-run.sh`)

## Step 1: Generate SSH Key for GitHub

### 1.1 Run the SSH key setup script

```bash
cd ~/PublishDemo
chmod +x setup-ssh-key.sh
./setup-ssh-key.sh
```

This will:
- Generate a new ed25519 SSH key pair
- Display the public key
- Configure SSH for GitHub

### 1.2 Add Public Key to GitHub

1. **Copy the public key** displayed by the script (starts with `ssh-ed25519`)

2. **Go to your GitHub repository:**
   ```
   https://github.com/thienanlktl/Pideployment/settings/keys
   ```

3. **Click "Add deploy key"**

4. **Fill in the form:**
   - **Title:** `Raspberry Pi Deploy Key` (or any descriptive name)
   - **Key:** Paste the public key
   - **Allow write access:** Unchecked (for read-only) or Checked (if you want to push)

5. **Click "Add key"**

### 1.3 Configure Git Remote

Update your git remote to use SSH:

```bash
cd ~/PublishDemo
git remote set-url origin git@github.com:thienanlktl/Pideployment.git
```

Or if using the SSH config alias:

```bash
git remote set-url origin git@github.com-iot-gui:thienanlktl/Pideployment.git
```

Or use HTTPS:

```bash
git remote set-url origin https://github.com/thienanlktl/Pideployment.git
```

### 1.4 Test SSH Connection

```bash
ssh -T git@github.com
```

You should see: `Hi thienanlktl! You've successfully authenticated...`

## Step 2: Install Webhook Listener Dependencies

The webhook listener requires Flask. Install it in your virtual environment:

```bash
cd ~/PublishDemo
source venv/bin/activate
pip install Flask
```

Or install all dependencies from requirements.txt:

```bash
pip install -r requirements.txt
```

## Step 3: Configure Webhook Secret

Generate a strong secret for webhook verification:

```bash
# Generate a random secret (32 characters)
python3 -c "import secrets; print(secrets.token_urlsafe(32))"
```

Copy the generated secret. You'll need it for:
1. Setting the `WEBHOOK_SECRET` environment variable
2. Configuring the GitHub webhook

## Step 4: Make Scripts Executable

```bash
cd ~/PublishDemo
chmod +x update-and-restart.sh
chmod +x webhook_listener.py
```

## Step 5: Test Update Script Manually

Before setting up the webhook, test the update script:

```bash
cd ~/PublishDemo
./update-and-restart.sh
```

This should:
- Pull latest code from GitHub
- Update Python dependencies
- Stop the running application (if any)
- Restart the application

Check the logs:
```bash
tail -f ~/PublishDemo/update.log
```

## Step 6: Set Up GitHub Webhook

### 6.1 Find Your Raspberry Pi's IP Address

```bash
hostname -I
```

Or check your router's admin panel for the Pi's IP address.

**Note:** If your Pi is behind a NAT/router without port forwarding, you'll need to:
- Set up port forwarding (port 9000) on your router, OR
- Use a tunnel service like ngrok (see "Alternative: Using ngrok" below)

### 6.2 Create Webhook in GitHub

1. **Go to your repository settings:**
   ```
   https://github.com/thienanlktl/Pideployment/settings/hooks
   ```

2. **Click "Add webhook"**

3. **Fill in the webhook form:**
   - **Payload URL:** `http://YOUR_PI_IP:9000/webhook`
     - Replace `YOUR_PI_IP` with your Pi's IP address
     - Example: `http://192.168.1.100:9000/webhook`
   
   - **Content type:** `application/json`
   
   - **Secret:** Paste the secret you generated in Step 3
   
   - **Which events would you like to trigger this webhook?**
     - Select: **Just the push event**
   
   - **Active:** Checked

4. **Click "Add webhook"**

### 6.3 Test Webhook

GitHub will send a test ping. Check the webhook delivery logs in GitHub to see if it was received.

## Step 7: Set Up Systemd Service (Recommended)

### 7.1 Edit the Service File

Edit `iot-gui-webhook.service` and update:
- `WorkingDirectory` - Path to your project directory
- `User` - Your username (default: `pi`)
- `ExecStart` - Path to webhook_listener.py
- `WEBHOOK_SECRET` - Your webhook secret from Step 3

```bash
nano ~/PublishDemo/iot-gui-webhook.service
```

Update these lines:
```ini
WorkingDirectory=/home/pi/PublishDemo
ExecStart=/home/pi/PublishDemo/venv/bin/python /home/pi/PublishDemo/webhook_listener.py
Environment="WEBHOOK_SECRET=your-secret-here"
```

### 7.2 Install and Start the Service

```bash
# Copy service file to systemd directory
sudo cp ~/PublishDemo/iot-gui-webhook.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable service to start on boot
sudo systemctl enable iot-gui-webhook.service

# Start the service
sudo systemctl start iot-gui-webhook.service

# Check status
sudo systemctl status iot-gui-webhook.service
```

### 7.3 View Service Logs

```bash
# View recent logs
sudo journalctl -u iot-gui-webhook.service -n 50

# Follow logs in real-time
sudo journalctl -u iot-gui-webhook.service -f
```

### 7.4 Service Management Commands

```bash
# Stop service
sudo systemctl stop iot-gui-webhook.service

# Start service
sudo systemctl start iot-gui-webhook.service

# Restart service
sudo systemctl restart iot-gui-webhook.service

# Disable auto-start on boot
sudo systemctl disable iot-gui-webhook.service
```

## Step 8: Test the Complete System

### 8.1 Make a Test Change

1. Make a small change to your code (e.g., add a comment)
2. Commit and push to GitHub:
   ```bash
   git add .
   git commit -m "Test deployment"
   git push origin main
   ```

### 8.2 Monitor the Update

Watch the webhook listener logs:
```bash
sudo journalctl -u iot-gui-webhook.service -f
```

Watch the update script logs:
```bash
tail -f ~/PublishDemo/update.log
```

The application should automatically:
1. Receive the webhook
2. Pull the latest code
3. Update dependencies (if needed)
4. Restart the application

## Alternative: Using Cron (Fallback Method)

If you can't set up a webhook (e.g., no public IP, firewall issues), use a cron job to check for updates periodically.

### Set Up Cron Job

```bash
crontab -e
```

Add this line to check every 10 minutes:
```cron
*/10 * * * * /home/pi/PublishDemo/update-and-restart.sh >> /home/pi/PublishDemo/cron.log 2>&1
```

Or every 5 minutes:
```cron
*/5 * * * * /home/pi/PublishDemo/update-and-restart.sh >> /home/pi/PublishDemo/cron.log 2>&1
```

**Note:** The update script is idempotent - it will only pull if there are changes, so running it frequently is safe.

## Alternative: Using ngrok (For Testing Behind NAT)

If your Pi is behind a NAT/router and you can't set up port forwarding, use ngrok for testing:

### Install ngrok

```bash
# Download ngrok (example for ARM)
wget https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz
tar xvzf ngrok-v3-stable-linux-arm.tgz
sudo mv ngrok /usr/local/bin/
```

### Start ngrok Tunnel

```bash
ngrok http 9000
```

This will display a public URL like: `https://abc123.ngrok.io`

### Update GitHub Webhook

Use the ngrok URL in your GitHub webhook:
- **Payload URL:** `https://abc123.ngrok.io/webhook`

**Note:** ngrok free tier URLs change on restart. For production, use a static domain or set up proper port forwarding.

## Troubleshooting

### Webhook Not Receiving Events

1. **Check webhook listener is running:**
   ```bash
   sudo systemctl status iot-gui-webhook.service
   ```

2. **Check firewall:**
   ```bash
   sudo ufw status
   sudo ufw allow 9000/tcp  # If firewall is enabled
   ```

3. **Check webhook delivery in GitHub:**
   - Go to repository settings → Webhooks
   - Click on your webhook
   - Check "Recent Deliveries" for errors

4. **Test webhook manually:**
   ```bash
   curl -X POST http://localhost:9000/webhook \
     -H "Content-Type: application/json" \
     -H "X-GitHub-Event: push" \
     -d '{"ref":"refs/heads/main"}'
   ```

### Git Pull Fails

1. **Check SSH key is added to GitHub:**
   ```bash
   ssh -T git@github.com
   ```

2. **Check git remote URL:**
   ```bash
   git remote -v
   ```

3. **Test git pull manually:**
   ```bash
   cd ~/PublishDemo
   git pull origin main
   ```

### Application Not Restarting

1. **Check update script logs:**
   ```bash
   tail -f ~/PublishDemo/update.log
   ```

2. **Check if application is running:**
   ```bash
   ps aux | grep iot_pubsub_gui.py
   ```

3. **Check PID file:**
   ```bash
   cat ~/PublishDemo/app.pid
   ```

### Permission Issues

1. **Make sure scripts are executable:**
   ```bash
   chmod +x ~/PublishDemo/update-and-restart.sh
   chmod +x ~/PublishDemo/webhook_listener.py
   ```

2. **Check file ownership:**
   ```bash
   ls -la ~/PublishDemo/
   ```

## Security Notes

1. **Webhook Secret:**
   - Use a strong, random secret (32+ characters)
   - Never commit the secret to git
   - Store it in the systemd service file or environment variables

2. **SSH Key:**
   - Keep the private key secure (chmod 600)
   - Use read-only deploy key if possible
   - Don't share the private key

3. **Firewall:**
   - Only expose port 9000 if necessary
   - Consider using a reverse proxy (nginx) with SSL
   - Use strong webhook secret to prevent unauthorized access

4. **Network:**
   - If possible, restrict webhook access to GitHub IPs
   - Use HTTPS with a reverse proxy for production

## Files Created

- `update-and-restart.sh` - Main update script
- `webhook_listener.py` - GitHub webhook listener
- `iot-gui-webhook.service` - Systemd service file
- `setup-ssh-key.sh` - SSH key generation script
- `requirements.txt` - Python dependencies (includes Flask)
- `DEPLOYMENT_SETUP.md` - This guide

## Quick Reference

### Check Webhook Status
```bash
sudo systemctl status iot-gui-webhook.service
```

### View Webhook Logs
```bash
sudo journalctl -u iot-gui-webhook.service -f
```

### View Update Logs
```bash
tail -f ~/PublishDemo/update.log
```

### Manual Update
```bash
cd ~/PublishDemo
./update-and-restart.sh
```

### Test Webhook Endpoint
```bash
curl http://localhost:9000/health
```

## Support

If you encounter issues:
1. Check the logs: `update.log` and `webhook.log`
2. Verify SSH key is added to GitHub
3. Verify webhook is configured correctly in GitHub
4. Test each component individually

