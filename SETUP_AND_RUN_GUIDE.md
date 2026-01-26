# Complete Setup, Update, and Run Guide

This is the **only guide you need** for setting up, updating, and running the IoT Pub/Sub GUI application on Raspberry Pi.

## Quick Start

### One-Command Setup (Recommended)

```bash
chmod +x setup-deployment-from-scratch.sh
./setup-deployment-from-scratch.sh
```

That's it! The script handles everything automatically.

---

## Part 1: Initial Setup

### Prerequisites

- Raspberry Pi with Raspberry Pi OS
- Internet connection
- SSH key file `id_ed25519` (optional - for SSH clone)

### Step 1: Prepare SSH Key (Optional but Recommended)

If you have an SSH key (`id_ed25519` and `id_ed25519.pub`):

1. Place both files in the same directory as `setup-deployment-from-scratch.sh`
2. The script will automatically detect and use them

If you don't have an SSH key:
- The script will clone via HTTPS
- You can set up SSH later

### Step 2: Run Setup Script

```bash
# Download or navigate to the script
cd ~/Pideployment  # or wherever you have the script

# Make it executable
chmod +x setup-deployment-from-scratch.sh

# Run it
./setup-deployment-from-scratch.sh
```

### What the Setup Script Does

The script automatically:

1. ✅ **Clones Repository**
   - Detects SSH key if present
   - Clones from `https://github.com/thienanlktl/Pideployment`
   - Sets up git remote

2. ✅ **Installs Dependencies**
   - System packages (PyQt6 dependencies, build tools)
   - Python virtual environment
   - Python packages (PyQt6, awsiotsdk, Flask, etc.)

3. ✅ **Starts Application**
   - Starts `iot_pubsub_gui.py` automatically
   - Runs in background
   - Logs to `logs/app.log`

4. ✅ **Sets Up Auto-Update**
   - Generates webhook secret
   - Installs webhook listener service
   - Starts webhook listener

### Step 3: Configure GitHub (Manual Steps Required)

**Yes, you need to manually create the webhook on GitHub.** The script cannot do this automatically, but it provides all the information you need.

**Important**: If your Pi IP changes on reboot, you'll need to update the webhook URL in GitHub. See "Handling Dynamic IP" section below.

After the script completes, you'll see output with:

#### 3.1: Add SSH Public Key to GitHub (One-Time)

1. **Copy the SSH public key** displayed by the script
2. Go to: `https://github.com/thienanlktl/Pideployment/settings/keys`
3. Click **"Add deploy key"**
4. **Title**: `Raspberry Pi Deploy Key` (or any name)
5. **Key**: Paste the public key
6. **Allow write access**: Unchecked (for read-only) or Checked (if you want to push)
7. Click **"Add key"**

**Note**: This is a one-time setup. The SSH key doesn't change.

#### 3.2: Add GitHub Webhook (Required for Auto-Update)

1. **Get webhook information**:
   ```bash
   # Run this helper script to get current IP and secret
   chmod +x get-webhook-info.sh
   ./get-webhook-info.sh
   ```
   
   Or manually:
   - **IP Address**: Run `hostname -I` or check script output
   - **Secret**: Check `.webhook_secret` file or script output

2. Go to: `https://github.com/thienanlktl/Pideployment/settings/hooks`

3. Click **"Add webhook"**

4. Fill in the form:
   - **Payload URL**: `http://YOUR_PI_IP:9000/webhook`
     - Replace `YOUR_PI_IP` with current IP address
     - Example: `http://192.168.1.100:9000/webhook`
   - **Content type**: Select `application/json`
   - **Secret**: Paste the webhook secret (from `.webhook_secret` file)
   - **Which events**: Select **"Just the push event"**
   - **Active**: Checked ✓

5. Click **"Add webhook"**

**Note**: 
- The **secret doesn't change** - it's saved in `.webhook_secret` file
- The **IP address may change** on reboot - see "Handling Dynamic IP" below
- GitHub will send a test ping. Check the "Recent Deliveries" tab to verify.

#### 3.3: Making Pi Accessible from Internet (Required for Webhooks)

**Important**: GitHub webhooks need to reach your Pi from the internet. Your Pi is likely behind a router, so you need to configure network access.

**Option A: Port Forwarding (Recommended)**

1. **Set static IP for Pi** (in router DHCP settings or Pi config)
2. **Port forward on router:**
   - Log into router admin (usually `192.168.1.1`)
   - Find "Port Forwarding" settings
   - Forward external port 9000 → Pi's IP port 9000
3. **Get your public IP:**
   ```bash
   curl ifconfig.me
   ```
4. **Use public IP in webhook URL:**
   - `http://YOUR_PUBLIC_IP:9000/webhook`

**Option B: Dynamic DNS + Port Forwarding (Best for Home Networks)**

1. **Set up DuckDNS** (free): https://www.duckdns.org
2. **Get domain**: e.g., `mypi.duckdns.org`
3. **Port forward** port 9000 (same as Option A)
4. **Use domain in webhook URL:**
   - `http://mypi.duckdns.org:9000/webhook`
5. **Domain auto-updates** when public IP changes

**Option C: ngrok (For Testing)**

1. **Install ngrok:**
   ```bash
   wget https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz
   tar xvzf ngrok-v3-stable-linux-arm.tgz
   sudo mv ngrok /usr/local/bin/
   ```
2. **Start tunnel:**
   ```bash
   ngrok http 9000
   ```
3. **Use ngrok URL in webhook:**
   - `https://abc123.ngrok.io/webhook` (HTTPS)

**See `WEBHOOK_NETWORK_SETUP.md` for detailed instructions.**

#### 3.4: Handling Dynamic IP (If IP Changes on Reboot)

If your Pi's **public IP** changes (not the local IP), you need to update the webhook URL in GitHub:

**Option 1: Quick Update (Recommended)**
```bash
# Get current IP and webhook info
./get-webhook-info.sh
```
Then update the webhook in GitHub with the new IP.

**Option 2: Set Static IP (Best Solution)**
Configure a static IP on your router or in Raspberry Pi OS:
- Router: Reserve IP for Pi's MAC address
- Pi: Configure static IP in `/etc/dhcpcd.conf`

**Option 3: Use Dynamic DNS**
- Set up DuckDNS, No-IP, or similar service
- Use domain name instead of IP in webhook URL
- Example: `http://mypi.duckdns.org:9000/webhook`

**Option 4: Use ngrok (For Testing)**
- See `GITHUB_WEBHOOK_SETUP.md` for ngrok setup
- Provides stable HTTPS URL
- Good for testing, not recommended for production

### Step 4: Verify Setup

```bash
# Check if application is running
ps aux | grep iot_pubsub_gui.py

# Check application logs
tail -f logs/app.log

# Check webhook service
sudo systemctl status iot-gui-webhook.service

# Test webhook health
curl http://localhost:9000/health
```

---

## Part 2: Running the Application

### Automatic Start (After Setup)

The application starts automatically after setup. It runs in the background.

### Manual Start

If you need to start it manually:

```bash
cd ~/Pideployment
source venv/bin/activate
python iot_pubsub_gui.py
```

Or use the launcher script:

```bash
cd ~/Pideployment
./setup-and-run.sh
```

### Check Application Status

```bash
# Check if running
ps aux | grep iot_pubsub_gui.py

# Check PID file
cat app.pid

# View logs
tail -f logs/app.log
```

### Stop Application

```bash
# Method 1: Using PID file
kill $(cat app.pid)

# Method 2: Find and kill process
pkill -f iot_pubsub_gui.py
```

### Restart Application

```bash
cd ~/Pideployment
./update-and-restart.sh
```

---

## Part 3: Auto-Update (Automatic)

### How It Works

When you push code to the `main` branch on GitHub:

1. GitHub sends a webhook to your Pi
2. Webhook listener receives it
3. Update script runs automatically
4. Application restarts with new code

**No manual intervention needed!**

### Manual Update (If Needed)

If you want to update manually:

```bash
cd ~/Pideployment
./update-and-restart.sh
```

This will:
- Pull latest code from GitHub
- Update Python dependencies
- Restart the application

### Verify Auto-Update is Working

1. **Check webhook service is running:**
   ```bash
   sudo systemctl status iot-gui-webhook.service
   ```

2. **Test by pushing code:**
   ```bash
   # Make a small change
   echo "# Test" >> iot_pubsub_gui.py
   git add iot_pubsub_gui.py
   git commit -m "Test update"
   git push origin main
   ```

3. **Watch the update:**
   ```bash
   # In one terminal - watch webhook logs
   sudo journalctl -u iot-gui-webhook.service -f
   
   # In another terminal - watch update logs
   tail -f update.log
   
   # In another terminal - watch app logs
   tail -f logs/app.log
   ```

You should see:
- Webhook received
- Code pulled
- Dependencies updated
- Application restarted

---

## Troubleshooting

### Application Won't Start

**Check logs:**
```bash
tail -f logs/app.log
```

**Check dependencies:**
```bash
source venv/bin/activate
python -c "import PyQt6; import awsiot"
```

**Check DISPLAY:**
```bash
echo $DISPLAY  # Should be :0
export DISPLAY=:0  # If not set
```

### Auto-Update Not Working

**Check webhook service:**
```bash
sudo systemctl status iot-gui-webhook.service
sudo journalctl -u iot-gui-webhook.service -n 50
```

**Check webhook in GitHub:**
- Go to repository settings → Webhooks
- Check "Recent Deliveries" for errors

**Test webhook manually:**
```bash
curl http://localhost:9000/health
```

**Test update script manually:**
```bash
cd ~/Pideployment
./update-and-restart.sh
```

### Git Pull Fails

**Check SSH key:**
```bash
ssh -T git@github.com
```

**Check git remote:**
```bash
git remote -v
```

**Test pull manually:**
```bash
git pull origin main
```

### Application Crashes

**Check logs:**
```bash
tail -f logs/app.log
```

**Check if dependencies are installed:**
```bash
source venv/bin/activate
pip list | grep -E "PyQt6|awsiotsdk"
```

**Reinstall dependencies:**
```bash
source venv/bin/activate
pip install -r requirements.txt
```

---

## Common Commands Reference

### Application Management

```bash
# Start application
cd ~/Pideployment
source venv/bin/activate
python iot_pubsub_gui.py &

# Stop application
pkill -f iot_pubsub_gui.py

# Restart application
./update-and-restart.sh

# Check status
ps aux | grep iot_pubsub_gui.py
cat app.pid
```

### Webhook Service Management

```bash
# Start service
sudo systemctl start iot-gui-webhook.service

# Stop service
sudo systemctl stop iot-gui-webhook.service

# Restart service
sudo systemctl restart iot-gui-webhook.service

# Check status
sudo systemctl status iot-gui-webhook.service

# View logs
sudo journalctl -u iot-gui-webhook.service -f
```

### Update Management

```bash
# Manual update
./update-and-restart.sh

# Check update logs
tail -f update.log

# Pull code only
git pull origin main
```

### Logs

```bash
# Application logs
tail -f logs/app.log

# Update logs
tail -f update.log

# Webhook logs
tail -f webhook.log
# OR
sudo journalctl -u iot-gui-webhook.service -f
```

---

## File Locations

- **Project Directory**: `~/Pideployment` (or where you cloned it)
- **Application**: `iot_pubsub_gui.py`
- **Virtual Environment**: `venv/`
- **Application PID**: `app.pid`
- **Application Logs**: `logs/app.log`
- **Update Logs**: `update.log`
- **Webhook Logs**: `webhook.log` or systemd journal

---

## Summary

### Setup (One Time)
```bash
./setup-deployment-from-scratch.sh
# Then manually add SSH key and webhook to GitHub (see Step 3 above)
```

### After Reboot (If IP Changed)

If your Pi IP address changed after reboot:

```bash
# Get current webhook information
./get-webhook-info.sh

# Then update webhook URL in GitHub with new IP
# Go to: https://github.com/thienanlktl/Pideployment/settings/hooks
# Click on your webhook → Edit → Update Payload URL
```

**Important Notes**:
- **SSH Key**: One-time setup, doesn't change
- **Webhook Secret**: Saved in `.webhook_secret`, doesn't change
- **IP Address**: May change on reboot - update webhook URL if needed
- **Best Solution**: Set static IP to avoid manual updates

### Running
- Application starts automatically after setup
- Runs in background
- Check with: `ps aux | grep iot_pubsub_gui.py`

### Auto-Update
- Automatic when you push to GitHub
- No action needed
- Or run manually: `./update-and-restart.sh`

---

## Need Help?

1. Check logs: `logs/app.log`, `update.log`, `webhook.log`
2. Check service status: `sudo systemctl status iot-gui-webhook.service`
3. Test components individually
4. See detailed troubleshooting section above

That's it! One script to set up, automatic updates, and the application runs in the background.

