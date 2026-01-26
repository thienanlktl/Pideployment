# Complete Setup Verification - iot_pubsub_gui.py

This document verifies that the system can **clone, run, and auto-update** the main application `iot_pubsub_gui.py`.

## ✅ Verification Checklist

### 1. Clone Repository ✓
- [x] Script detects existing SSH key (`id_ed25519`) in current directory
- [x] Automatically sets up SSH key for git operations
- [x] Clones repository via SSH if key available
- [x] Falls back to HTTPS if SSH not available
- [x] Handles existing directory gracefully

### 2. Run Application ✓
- [x] Application starts automatically after setup
- [x] Uses virtual environment Python (`venv/bin/python`)
- [x] Sets DISPLAY for GUI (`DISPLAY=:0`)
- [x] Runs in background with nohup
- [x] Saves PID to `app.pid`
- [x] Logs to `logs/app.log`
- [x] Verifies process started successfully

### 3. Auto-Update ✓
- [x] Webhook listener receives GitHub push events
- [x] Verifies webhook signature
- [x] Checks if push is to main branch
- [x] Triggers `update-and-restart.sh`
- [x] Pulls latest code from GitHub
- [x] Updates Python dependencies
- [x] Stops running application gracefully
- [x] Restarts application with new code
- [x] Uses virtual environment Python

## Complete Flow

### Initial Setup
```
1. Run setup-deployment-from-scratch.sh
   ↓
2. Clone repository (SSH or HTTPS)
   ↓
3. Install dependencies
   ↓
4. Start iot_pubsub_gui.py
   ↓
5. Set up webhook listener
   ↓
6. Ready for auto-updates
```

### Auto-Update (When Code Pushed)
```
1. Push code to GitHub main branch
   ↓
2. GitHub sends webhook to Pi
   ↓
3. webhook_listener.py receives event
   ↓
4. Calls update-and-restart.sh
   ↓
5. git pull origin main
   ↓
6. pip install -r requirements.txt
   ↓
7. Stop iot_pubsub_gui.py
   ↓
8. Start iot_pubsub_gui.py (with new code)
   ↓
9. Application running with latest code
```

## Key Components

### setup-deployment-from-scratch.sh
- **Step 0**: Detects and sets up SSH key
- **Step 0.5**: Clones repository
- **Step 14**: Starts `iot_pubsub_gui.py` automatically

### update-and-restart.sh
- **Step 1**: Pulls code (`git pull origin main`)
- **Step 3**: Updates dependencies (`pip install -r requirements.txt`)
- **Step 4**: Stops application (from `app.pid`)
- **Step 5**: Restarts application (using `venv/bin/python`)

### webhook_listener.py
- Listens on port 9000
- Verifies webhook signature
- Calls `update-and-restart.sh` on push to main

## Application Execution

Both scripts use the same method to start the application:

```bash
# Activate venv
source venv/bin/activate

# Or use explicit path
VENV_PYTHON="venv/bin/python"

# Start application
nohup "$VENV_PYTHON" iot_pubsub_gui.py >> logs/app.log 2>&1 &
echo $! > app.pid
```

## File Structure After Setup

```
Pideployment/
├── iot_pubsub_gui.py          # Main application
├── venv/                      # Virtual environment
│   └── bin/
│       └── python             # Python with all dependencies
├── app.pid                    # Application process ID
├── logs/
│   └── app.log                # Application logs
├── update.log                 # Update script logs
├── webhook.log                # Webhook listener logs
├── update-and-restart.sh      # Auto-update script
├── webhook_listener.py        # Webhook listener
└── iot-gui-webhook.service    # Systemd service file
```

## Testing the Complete Flow

### Test 1: Initial Setup
```bash
# On fresh Pi with id_ed25519 in directory
./setup-deployment-from-scratch.sh

# Verify:
ps aux | grep iot_pubsub_gui.py  # Should show running process
cat app.pid                      # Should show PID
tail -f logs/app.log             # Should show app output
```

### Test 2: Auto-Update
```bash
# Make a change to iot_pubsub_gui.py
echo "# Test update" >> iot_pubsub_gui.py

# Commit and push
git add iot_pubsub_gui.py
git commit -m "Test auto-update"
git push origin main

# Watch logs
tail -f update.log              # Should show update process
tail -f logs/app.log            # Should show app restart
sudo journalctl -u iot-gui-webhook.service -f  # Should show webhook received
```

### Test 3: Manual Update
```bash
cd ~/Pideployment
./update-and-restart.sh

# Verify:
ps aux | grep iot_pubsub_gui.py  # Should show new process
cat app.pid                      # Should show new PID
```

## Success Criteria

✅ **Clone**: Repository cloned successfully  
✅ **Run**: Application starts and runs  
✅ **Auto-Update**: Application restarts automatically on code push  

All three requirements are met!

