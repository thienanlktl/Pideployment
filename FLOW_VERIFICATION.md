# Complete Flow Verification

## End-to-End Flow

### 1. Initial Setup (One-time)
```bash
./setup-deployment-from-scratch.sh
```

**What happens:**
- ✅ Clones repository from GitHub
- ✅ Installs all system dependencies
- ✅ Creates virtual environment
- ✅ Installs Python dependencies (including Flask)
- ✅ Generates SSH key for GitHub
- ✅ Configures git remote
- ✅ Generates webhook secret
- ✅ Sets up ngrok with pre-configured token
- ✅ Creates GitHub webhook automatically (using .github_token)
- ✅ Installs and starts webhook listener service
- ✅ Starts Python application

### 2. Update Flow (Automatic on Push)

**When code is merged to `main` branch:**

1. **GitHub sends webhook POST** → `https://xxxx.ngrok.io/webhook`
2. **ngrok tunnel** → Forwards to `localhost:9000`
3. **webhook_listener.py** → Receives and verifies request
4. **Triggers update-and-restart.sh** → Runs automatically
5. **Git pull** → Pulls latest code from GitHub
6. **Dependency update** → Updates Python packages if needed
7. **Stop app** → Gracefully stops running `iot_pubsub_gui.py`
8. **Restart app** → Starts `iot_pubsub_gui.py` with new code

## Scripts Updated

### ✅ `setup-deployment-from-scratch.sh`
- Auto-detects and uses `.github_token` file
- Automatically sets up ngrok with pre-configured token
- Automatically creates GitHub webhook
- No prompts needed (fully automated)

### ✅ `update-and-restart.sh`
- Handles SSH authentication for git pull
- Falls back to HTTPS if SSH fails
- Properly restarts Python application
- Uses venv Python explicitly

### ✅ `webhook_listener.py`
- Calls `update-and-restart.sh` with proper environment
- Handles DISPLAY variable for GUI
- Ensures venv Python is in PATH
- Uses bash explicitly for script execution

### ✅ `iot-gui-webhook.service`
- Loads webhook secret from `.webhook_secret` file
- Uses correct paths (replaced by setup script)
- Properly activates venv
- Sets DISPLAY for GUI

### ✅ `create-github-webhook.sh`
- Auto-detects `.github_token` file
- Auto-detects ngrok URL from `.ngrok_url` file
- Non-interactive mode support
- Updates existing webhook if found

### ✅ `requirements.txt`
- Includes Flask>=2.0.0 for webhook listener
- All dependencies specified

## Testing the Flow

### Test 1: Manual Update
```bash
cd ~/Pideployment
./update-and-restart.sh
```

**Expected:**
- Git pull succeeds
- Dependencies updated
- App stops and restarts
- New code is running

### Test 2: Webhook Trigger
1. Make a small change to code
2. Commit and push to `main` branch
3. Watch logs:
   ```bash
   sudo journalctl -u iot-gui-webhook.service -f
   ```

**Expected:**
- Webhook received
- `update-and-restart.sh` triggered
- Code pulled
- App restarted

### Test 3: Health Check
```bash
# Local
curl http://localhost:9000/health

# Public (after ngrok)
curl https://xxxx.ngrok.io/health
```

**Expected:**
- Returns JSON with status "healthy"

## Troubleshooting

### Webhook not receiving events?
1. Check ngrok is running: `sudo systemctl status iot-gui-ngrok.service`
2. Check webhook service: `sudo systemctl status iot-gui-webhook.service`
3. Get current URL: `./get-ngrok-url.sh`
4. Verify in GitHub: https://github.com/thienanlktl/Pideployment/settings/hooks

### App not restarting?
1. Check webhook logs: `sudo journalctl -u iot-gui-webhook.service -f`
2. Check update logs: `tail -f ~/Pideployment/update.log`
3. Check app logs: `tail -f ~/Pideployment/logs/app.log`

### Git pull failing?
1. Check SSH key is added to GitHub
2. Check git remote: `git remote -v`
3. Test SSH: `ssh -T git@github.com`
4. Try manual pull: `git pull origin main`

## All Systems Ready! 🚀

The complete flow is now automated and working:
- ✅ Setup: One command
- ✅ Updates: Automatic on push
- ✅ Restart: Automatic
- ✅ No manual steps needed

