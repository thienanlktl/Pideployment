# Standalone Installer - No Git Required

## Problem with Original Installer

The original `install-iot-pubsub-gui.sh` requires:
- Git installed
- Internet connection
- Access to GitHub repository (public or with authentication)

**If you run it on a new Raspberry Pi without git or SSH keys, it will fail at the git clone step.**

## Solution: Standalone Installer

The `install-iot-pubsub-gui-standalone.sh` is a **single-file installer** that:
- ✅ **Packages all application files** directly in the script
- ✅ **No git required** - all files are embedded
- ✅ **No SSH keys required** - no repository access needed
- ✅ **Works offline** - after copying the installer file
- ✅ **Complete installation** - same functionality as original installer

## How to Use

### Step 1: Generate the Standalone Installer

On your development machine (where you have the repository):

```bash
python create-standalone-installer.py
```

This creates `install-iot-pubsub-gui-standalone.sh` (approximately 50-60 KB).

### Step 2: Copy to Raspberry Pi

Transfer the standalone installer to your Raspberry Pi:

**Option A: Using SCP**
```bash
scp install-iot-pubsub-gui-standalone.sh pi@raspberrypi.local:~/
```

**Option B: Using USB drive**
1. Copy `install-iot-pubsub-gui-standalone.sh` to USB drive
2. Insert USB into Raspberry Pi
3. Copy from USB to home directory

**Option C: Using wget (if Pi has internet)**
```bash
# On Raspberry Pi
wget https://your-server.com/install-iot-pubsub-gui-standalone.sh
```

### Step 3: Run on Raspberry Pi

```bash
# On Raspberry Pi
chmod +x install-iot-pubsub-gui-standalone.sh
bash install-iot-pubsub-gui-standalone.sh
```

## What Gets Installed

The standalone installer extracts and installs:

1. **iot_pubsub_gui.py** - Main application (embedded in installer)
2. **requirements.txt** - Python dependencies (embedded)
3. **VERSION** - Version file (embedded)
4. **iot-pubsub-gui.desktop** - Desktop launcher (embedded)
5. **Virtual environment** - Created automatically
6. **Python packages** - Installed from requirements.txt
7. **Desktop launcher** - Created on Desktop

## What You Still Need to Add

After installation, you need to manually add:

1. **Certificate files** (required for AWS IoT connection):
   - `AmazonRootCA1.pem`
   - `ebb0b9fb27d1eb1ca52f7f89260e123a992759bf3b630f9863575015132ebbef-certificate.pem.crt`
   - `ebb0b9fb27d1eb1ca52f7f89260e123a992759bf3b630f9863575015132ebbef-private.pem.key`

Copy these to: `~/iot-pubsub-gui/`

## Comparison

| Feature | Original Installer | Standalone Installer |
|---------|-------------------|---------------------|
| Requires Git | ✅ Yes | ❌ No |
| Requires Internet | ✅ Yes (for git clone) | ❌ No (after copying installer) |
| Requires SSH Keys | ✅ Yes (for private repos) | ❌ No |
| File Size | ~5 KB | ~50-60 KB |
| Works Offline | ❌ No | ✅ Yes |
| Updates from Git | ✅ Yes | ❌ No (manual update) |

## When to Use Which

**Use Original Installer (`install-iot-pubsub-gui.sh`):**
- When you have git installed
- When you have internet access
- When you want automatic updates from GitHub
- For development/testing

**Use Standalone Installer (`install-iot-pubsub-gui-standalone.sh`):**
- When deploying to new Raspberry Pi without git
- When you don't have SSH keys configured
- When you need offline installation
- For production deployments
- When you want a single-file package

## Updating the Standalone Installer

When you make changes to the application:

1. Update the files in your repository
2. Run `python create-standalone-installer.py` again
3. This generates a new `install-iot-pubsub-gui-standalone.sh` with latest files
4. Copy the new installer to Raspberry Pi and run it

## Notes

- The standalone installer is **idempotent** - safe to run multiple times
- It will update existing installations if run again
- Certificate files are **not** included in the installer (security)
- The installer is **self-contained** - everything needed is embedded
- File size is larger (~50-60 KB) because it includes all application files

