# Deployment Files Summary

This document describes all the files created for the automated deployment system.

## Core Deployment Files

### `update-and-restart.sh`
**Purpose:** Main script that pulls code, updates dependencies, and restarts the application.

**What it does:**
- Pulls latest code from GitHub (main branch)
- Checks/creates virtual environment
- Updates Python dependencies from requirements.txt
- Gracefully stops running application
- Restarts the application in background
- Logs all operations to `update.log`

**Usage:**
```bash
./update-and-restart.sh
```

**Called by:**
- Webhook listener (when GitHub push event received)
- Cron job (if using cron fallback)
- Manual execution

---

### `webhook_listener.py`
**Purpose:** Flask web server that listens for GitHub webhook events.

**What it does:**
- Listens on port 9000 for GitHub webhook POST requests
- Verifies webhook signature using HMAC SHA256
- Checks if push event is to main branch
- Triggers `update-and-restart.sh` when valid push detected
- Provides health check endpoint at `/health`
- Logs all events to `webhook.log`

**Usage:**
```bash
source venv/bin/activate
export WEBHOOK_SECRET="your-secret-here"
python webhook_listener.py
```

**Environment Variables:**
- `WEBHOOK_SECRET` - Secret for webhook verification (required)
- `WEBHOOK_PORT` - Port to listen on (default: 9000)
- `WEBHOOK_HOST` - Host to bind to (default: 0.0.0.0)
- `GIT_BRANCH` - Branch to monitor (default: main)

---

### `iot-gui-webhook.service`
**Purpose:** Systemd service file to run webhook listener as a background daemon.

**What it does:**
- Runs webhook_listener.py as a system service
- Auto-starts on boot
- Restarts automatically on failure
- Logs to systemd journal

**Usage:**
```bash
sudo cp iot-gui-webhook.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable iot-gui-webhook.service
sudo systemctl start iot-gui-webhook.service
```

**Note:** Update paths in the file to match your project directory before installing.

---

## Setup Scripts

### `setup-ssh-key.sh`
**Purpose:** Generates SSH key pair for GitHub authentication.

**What it does:**
- Generates ed25519 SSH key pair
- Sets proper permissions (600)
- Configures SSH config for GitHub
- Displays public key for adding to GitHub
- Provides instructions for GitHub setup

**Usage:**
```bash
chmod +x setup-ssh-key.sh
./setup-ssh-key.sh
```

**Output:**
- Private key: `~/.ssh/id_ed25519_iot_gui`
- Public key: `~/.ssh/id_ed25519_iot_gui.pub` (displayed for copying)

---

### `setup-cron-fallback.sh`
**Purpose:** Sets up cron job for periodic update checks (fallback method).

**What it does:**
- Interactive setup for cron schedule
- Adds cron job to run `update-and-restart.sh` periodically
- Configures logging to `cron.log`

**Usage:**
```bash
chmod +x setup-cron-fallback.sh
./setup-cron-fallback.sh
```

**When to use:**
- If you can't set up webhook (no public IP, firewall issues)
- As a backup to webhook method
- For testing purposes

---

### `test-deployment.sh`
**Purpose:** Tests deployment system components.

**What it does:**
- Checks if all required files exist
- Verifies script permissions
- Checks virtual environment and dependencies
- Verifies git repository and SSH setup
- Tests webhook listener syntax
- Checks systemd service status

**Usage:**
```bash
chmod +x test-deployment.sh
./test-deployment.sh
```

---

## Configuration Files

### `requirements.txt`
**Purpose:** Python dependencies list.

**Contents:**
- PyQt6 (GUI framework)
- awsiotsdk (AWS IoT SDK)
- Flask (webhook listener)
- Other dependencies

**Usage:**
```bash
source venv/bin/activate
pip install -r requirements.txt
```

---

## Documentation Files

### `DEPLOYMENT_SETUP.md`
**Purpose:** Complete step-by-step setup guide.

**Contents:**
- Detailed instructions for all setup steps
- GitHub configuration
- Webhook setup
- Systemd service setup
- Troubleshooting guide
- Security notes

---

### `QUICK_DEPLOYMENT_REFERENCE.md`
**Purpose:** Quick reference for common commands.

**Contents:**
- One-line commands
- Service management
- Log file locations
- Testing commands
- Troubleshooting quick fixes

---

## Generated Files (Created at Runtime)

### `update.log`
**Purpose:** Log file for update-and-restart.sh operations.

**Location:** `~/PublishDemo/update.log`

**Contents:**
- Timestamped log of all update operations
- Git pull results
- Dependency installation results
- Application start/stop events

---

### `webhook.log`
**Purpose:** Log file for webhook listener.

**Location:** `~/PublishDemo/webhook.log`

**Contents:**
- Webhook events received
- Signature verification results
- Update script execution results

---

### `cron.log`
**Purpose:** Log file for cron job executions.

**Location:** `~/PublishDemo/cron.log`

**Contents:**
- Output from periodic update checks
- Only created if using cron fallback

---

### `app.pid`
**Purpose:** PID file for running application.

**Location:** `~/PublishDemo/app.pid`

**Contents:**
- Process ID of running application
- Used to gracefully stop application on restart

---

## File Permissions

All shell scripts should be executable:
```bash
chmod +x *.sh
```

SSH private key should be:
```bash
chmod 600 ~/.ssh/id_ed25519_iot_gui
```

---

## Directory Structure

```
~/PublishDemo/
├── update-and-restart.sh          # Main update script
├── webhook_listener.py             # Webhook listener
├── iot-gui-webhook.service         # Systemd service file
├── setup-ssh-key.sh               # SSH key setup
├── setup-cron-fallback.sh        # Cron setup
├── test-deployment.sh             # Test script
├── requirements.txt               # Python dependencies
├── DEPLOYMENT_SETUP.md            # Full setup guide
├── QUICK_DEPLOYMENT_REFERENCE.md  # Quick reference
├── DEPLOYMENT_FILES_SUMMARY.md    # This file
├── venv/                          # Virtual environment
├── update.log                     # Update script logs
├── webhook.log                    # Webhook listener logs
├── cron.log                       # Cron job logs (if using cron)
└── app.pid                        # Application PID file
```

---

## Workflow

1. **Developer pushes code to GitHub** → GitHub sends webhook event
2. **Webhook listener receives event** → Verifies signature → Checks branch
3. **Update script triggered** → Pulls code → Updates deps → Restarts app
4. **Application restarted** → Running with latest code

---

## Security Considerations

1. **SSH Key:**
   - Private key stored securely (chmod 600)
   - Public key added to GitHub as deploy key
   - Read-only access recommended

2. **Webhook Secret:**
   - Strong random secret (32+ characters)
   - Stored in systemd service file or environment
   - Never committed to git

3. **Network:**
   - Port 9000 exposed (consider firewall rules)
   - Webhook signature verification prevents unauthorized access
   - Consider reverse proxy with SSL for production

---

## Support

For issues or questions:
1. Check `DEPLOYMENT_SETUP.md` for detailed instructions
2. Run `./test-deployment.sh` to diagnose issues
3. Check log files: `update.log`, `webhook.log`
4. Review systemd logs: `sudo journalctl -u iot-gui-webhook.service`

