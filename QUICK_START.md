# Quick Start Guide - AWS IoT Pub/Sub GUI

## One-Click Launch (Easiest)

### Step 1: Make Script Executable
```bash
chmod +x setup-and-run.sh
```

### Step 2: Create Desktop Launcher (Optional)
```bash
chmod +x create-desktop-launcher.sh
./create-desktop-launcher.sh
```

### Step 3: Launch!
- **Option A:** Double-click `setup-and-run.sh` in file manager
- **Option B:** Double-click the desktop icon (if created)
- **Option C:** Run in terminal: `./setup-and-run.sh`

## What Happens

1. ✅ First time: Installs everything (30-60 min for PyQt6)
2. ✅ Next times: Launches instantly (< 10 seconds)
3. ✅ Safe to run multiple times (idempotent)

## Requirements

- Raspberry Pi with Raspberry Pi OS
- Internet connection
- Certificate files in project folder (optional, for AWS IoT connection)

## Troubleshooting

**"Permission denied"**
```bash
chmod +x setup-and-run.sh
```

**PyQt6 fails to install**
```bash
sudo apt-get install -y libxcb-xinerama0 libxkbcommon-x11-0 libqt6gui6
./setup-and-run.sh
```

**No window appears**
- Make sure you're on the Pi desktop (not SSH)
- Or use: `ssh -X pi@raspberrypi-ip`

For detailed instructions, see `SETUP_INSTRUCTIONS.md`

