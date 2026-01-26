# Auto-Update Flow Documentation

This document explains how the complete auto-update system works for `iot_pubsub_gui.py`.

## Complete Flow

### 1. Initial Setup (setup-deployment-from-scratch.sh)

When you run `setup-deployment-from-scratch.sh`:

1. **Clones Repository**
   - Detects existing SSH key (`id_ed25519`) if present
   - Clones via SSH if key available, otherwise HTTPS
   - Sets up git remote

2. **Installs Dependencies**
   - System packages (PyQt6 dependencies, build tools)
   - Python virtual environment
   - Python packages (PyQt6, awsiotsdk, Flask, etc.)

3. **Starts Application**
   - Checks if `iot_pubsub_gui.py` exists
   - Stops any existing instance
   - Starts application in background using venv Python
   - Saves PID to `app.pid`
   - Logs to `logs/app.log`

4. **Sets Up Webhook Listener**
   - Generates webhook secret
   - Installs systemd service
   - Starts webhook listener on port 9000

### 2. Auto-Update Flow (When Code is Pushed to GitHub)

```
GitHub Push Event
    ↓
GitHub Webhook → http://PI_IP:9000/webhook
    ↓
webhook_listener.py
    ├─ Verifies webhook signature
    ├─ Checks if push is to main branch
    └─ Calls update-and-restart.sh
            ↓
    update-and-restart.sh
        ├─ Step 1: git pull origin main
        ├─ Step 2: Activate venv
        ├─ Step 3: pip install -r requirements.txt (updates deps)
        ├─ Step 4: Stop running app (kill process from app.pid)
        └─ Step 5: Start app (using venv Python)
                ↓
        Application Restarted with New Code
```

## Key Files

### setup-deployment-from-scratch.sh
- **Purpose**: Initial setup from scratch
- **What it does**:
  - Clones repository
  - Sets up environment
  - Installs dependencies
  - Starts application
  - Configures webhook listener

### update-and-restart.sh
- **Purpose**: Update code and restart application
- **What it does**:
  - Pulls latest code from GitHub
  - Updates Python dependencies
  - Stops running application
  - Restarts application with new code
- **Called by**: webhook_listener.py or cron job

### webhook_listener.py
- **Purpose**: Listen for GitHub webhook events
- **What it does**:
  - Listens on port 9000
  - Verifies webhook signature
  - Checks if push is to main branch
  - Triggers update-and-restart.sh
- **Runs as**: systemd service (iot-gui-webhook.service)

## Application Lifecycle

### Initial Start (Setup Script)
```bash
# In setup-deployment-from-scratch.sh Step 14
1. Check if app is running → Stop if needed
2. Activate venv
3. Set DISPLAY=:0 for GUI
4. Start: nohup venv/bin/python iot_pubsub_gui.py >> logs/app.log 2>&1 &
5. Save PID to app.pid
```

### Auto-Update Restart (Update Script)
```bash
# In update-and-restart.sh Step 5
1. Pull latest code: git pull origin main
2. Update dependencies: pip install -r requirements.txt
3. Stop app: kill process from app.pid or pgrep
4. Activate venv
5. Set DISPLAY=:0 for GUI
6. Start: nohup venv/bin/python iot_pubsub_gui.py >> logs/app.log 2>&1 &
7. Save PID to app.pid
```

## File Locations

- **Application**: `$PROJECT_DIR/iot_pubsub_gui.py`
- **PID File**: `$PROJECT_DIR/app.pid`
- **Application Logs**: `$PROJECT_DIR/logs/app.log`
- **Update Logs**: `$PROJECT_DIR/update.log`
- **Webhook Logs**: `$PROJECT_DIR/webhook.log`
- **Virtual Environment**: `$PROJECT_DIR/venv/`

## Verification

### Check if Application is Running
```bash
# Method 1: Check PID file
cat app.pid
ps -p $(cat app.pid)

# Method 2: Check process
pgrep -f iot_pubsub_gui.py

# Method 3: Check logs
tail -f logs/app.log
```

### Test Auto-Update
1. Make a change to `iot_pubsub_gui.py`
2. Commit and push to GitHub:
   ```bash
   git add iot_pubsub_gui.py
   git commit -m "Test update"
   git push origin main
   ```
3. Watch webhook logs:
   ```bash
   sudo journalctl -u iot-gui-webhook.service -f
   ```
4. Watch update logs:
   ```bash
   tail -f update.log
   ```
5. Application should automatically restart with new code

## Troubleshooting

### Application Not Starting
- Check logs: `tail -f logs/app.log`
- Check venv: `source venv/bin/activate && python -c "import PyQt6"`
- Check DISPLAY: `echo $DISPLAY` (should be :0)

### Auto-Update Not Working
- Check webhook service: `sudo systemctl status iot-gui-webhook.service`
- Check webhook logs: `tail -f webhook.log`
- Verify webhook in GitHub: Check delivery logs
- Test manually: `./update-and-restart.sh`

### Git Pull Fails
- Check SSH key: `ssh -T git@github.com`
- Check remote: `git remote -v`
- Test pull: `git pull origin main`

## Summary

The system ensures:
1. ✅ **Clone**: Repository is cloned automatically
2. ✅ **Run**: Application starts automatically after setup
3. ✅ **Auto-Update**: Application restarts automatically when code is pushed to GitHub

All steps use the virtual environment Python to ensure dependencies are correct.

