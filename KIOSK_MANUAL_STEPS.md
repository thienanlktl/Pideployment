# Kiosk Setup: Detailed Manual Steps

This document lists **every step you must run manually**, in order, to complete the full Raspberry Pi kiosk setup (Wayland / labwc). Use it as a checklist when you prefer to run steps by hand, or to understand what **[setup-kiosk.sh](setup-kiosk.sh)** does under the hood.

**Prerequisites:** Raspberry Pi 4/5, Raspberry Pi OS 64-bit Bookworm (or newer), Wayland session with labwc. Log in as user `pi` (or adjust paths).

---

## Use setup-kiosk.sh (recommended)

The script **[setup-kiosk.sh](setup-kiosk.sh)** automates Phases 2–6 below (and optionally SSH key-only). See [KIOSK_SETUP.md — How to apply setup-kiosk.sh](KIOSK_SETUP.md#how-to-apply-setup-kiosksh) for full details.

**Fresh Pi (no code yet) — clone via SSH using keys in `~/.ssh`:**

1. Put your SSH key in `~/.ssh` (copy from another machine or generate and add the public key to GitHub).
2. Download the script (do **not** put it inside the app directory):
   ```bash
   curl -sL https://raw.githubusercontent.com/thienanlktl/Pideployment/main/setup-kiosk.sh -o /home/pi/setup-kiosk.sh
   chmod +x /home/pi/setup-kiosk.sh
   ```
3. Run with `--clone` so it pulls the repo via SSH and runs all setup:
   ```bash
   cd /home/pi
   ./setup-kiosk.sh --clone --reboot
   ```
   For a public repo without an SSH key on the Pi: use `./setup-kiosk.sh --clone-https --reboot`.

**App already at `/home/pi/iot-pubsub-gui`:**

```bash
cd /home/pi/iot-pubsub-gui
chmod +x setup-kiosk.sh
./setup-kiosk.sh --reboot
```

**What setup-kiosk.sh does:** system packages (Phase 2), venv + Python deps (Phase 3), labwc autostart (Phase 4), labwc rc.xml — remove Alt+Tab/Alt+F4 (Phase 5), raspi-config autologin (Phase 6). Optional: `--overlayfs`, `--ssh-key-only`. Phases 7 (desktop/taskbar) and 8 (SSH) are manual if needed.

---

## Phase 1: Get the app on the Pi

Use this phase only if you are **not** using `setup-kiosk.sh --clone`. Otherwise the script does the clone for you.

### Step 1.1 – Clone or copy the repository

**Option A – Use setup-kiosk.sh to clone (SSH from ~/.ssh):**

- Put your private key in `~/.ssh`, download `setup-kiosk.sh` to `/home/pi`, then run:
  ```bash
  cd /home/pi
  ./setup-kiosk.sh --clone --reboot
  ```
  This creates `/home/pi/iot-pubsub-gui` and runs all later phases. Skip to Phase 9 (reboot) after the script finishes.

**Option B – Clone with git manually:**

```bash
cd /home/pi
git clone https://github.com/thienanlktl/Pideployment.git iot-pubsub-gui
cd iot-pubsub-gui
```

If the repo is private, use SSH (keys in `~/.ssh`):

```bash
git clone git@github.com:thienanlktl/Pideployment.git iot-pubsub-gui
cd iot-pubsub-gui
```

**Option C – Copy from USB or another machine:**

- Copy the whole project folder (including `iot_pubsub_gui.py`, `requirements.txt`, `ensure_venv.sh`, `monitor.sh`, `setup-kiosk.sh`, `labwc-autostart.example`, certificates, etc.) to `/home/pi/iot-pubsub-gui`.

Then:

```bash
cd /home/pi/iot-pubsub-gui
```

---

### Step 1.2 – Confirm app directory

```bash
ls -la /home/pi/iot-pubsub-gui
```

You should see at least: `iot_pubsub_gui.py`, `requirements.txt`, `ensure_venv.sh`, `monitor.sh`, `setup-kiosk.sh`, `labwc-autostart.example`, and your certificate files (e.g. `*.pem`, `*.crt`, `*.key`).

---

## Phase 2: System packages

*(setup-kiosk.sh does this: `apt-get update` and installs unclutter, python3, python3-pip, python3-venv, python3-dev.)*

### Step 2.1 – Update package list

```bash
sudo apt-get update
```

### Step 2.2 – Install unclutter (hides cursor when idle)

```bash
sudo apt-get install -y unclutter
```

### Step 2.3 – (Optional) Install full one-click installer dependencies

If you prefer to use `install.sh` instead of only `ensure_venv.sh`, install system deps first:

```bash
sudo apt-get install -y git python3 python3-pip python3-venv python3-dev build-essential sqlite3 libsqlite3-dev
```

You can skip this if you only run `ensure_venv.sh` and already have `python3` and `python3-venv` (usually present on Pi OS).

---

## Phase 3: Virtual environment and Python packages

*(setup-kiosk.sh does this: `chmod +x ensure_venv.sh monitor.sh` and runs `./ensure_venv.sh`.)*

### Step 3.1 – Go to app directory

```bash
cd /home/pi/iot-pubsub-gui
```

### Step 3.2 – Make scripts executable

```bash
chmod +x ensure_venv.sh monitor.sh
```

### Step 3.3 – Create venv and install all packages

```bash
./ensure_venv.sh
```

- This creates `venv/` if missing, runs `pip install -r requirements.txt`, and verifies all imports (PyQt6, awsiotsdk, awscrt, cryptography, requests, GitPython, etc.).
- If any step fails, fix the error (e.g. network, missing system libs) and run `./ensure_venv.sh` again.

### Step 3.4 – (Optional) Test the app once in kiosk mode

```bash
/home/pi/iot-pubsub-gui/venv/bin/python3 /home/pi/iot-pubsub-gui/iot_pubsub_gui.py --kiosk
```

- You should see the app fullscreen. Close it (e.g. if you temporarily allow closing for testing) or reboot after configuring autostart.

---

## Phase 4: labwc autostart (start app on login)

*(setup-kiosk.sh does this: creates `~/.config/labwc/autostart` with the correct APP_DIR.)*

### Step 4.1 – Create labwc config directory

```bash
mkdir -p ~/.config/labwc
```

### Step 4.2 – Copy autostart file

```bash
cp /home/pi/iot-pubsub-gui/labwc-autostart.example ~/.config/labwc/autostart
```

### Step 4.3 – (Optional) Edit autostart if app is not in `/home/pi/iot-pubsub-gui`

If your app is in a different path (e.g. `/home/pi/my-kiosk`):

```bash
nano ~/.config/labwc/autostart
```

Change the line `APP_DIR="/home/pi/iot-pubsub-gui"` to your path. Save and exit (Ctrl+O, Enter, Ctrl+X).

### Step 4.4 – Ensure autostart is executable (some setups require it)

```bash
chmod +x ~/.config/labwc/autostart
```

---

## Phase 5: labwc rc.xml (disable escape shortcuts)

*(setup-kiosk.sh does this: copies system rc.xml and removes A-Tab and A-F4 keybind blocks with sed. Use `--no-rcxml` to skip.)*

### Step 5.1 – Copy system rc.xml to your config (if you don’t have one yet)

```bash
cp /etc/xdg/labwc/rc.xml ~/.config/labwc/rc.xml 2>/dev/null || true
```

If the file already exists at `~/.config/labwc/rc.xml`, this may overwrite it. Back it up first if needed:

```bash
cp ~/.config/labwc/rc.xml ~/.config/labwc/rc.xml.bak 2>/dev/null || true
cp /etc/xdg/labwc/rc.xml ~/.config/labwc/rc.xml 2>/dev/null || true
```

### Step 5.2 – Open rc.xml for editing

```bash
nano ~/.config/labwc/rc.xml
```

### Step 5.3 – Find and remove/disable keybindings

Search (Ctrl+W in nano) for:

- `A-Tab` – Alt+Tab (cycle windows). Remove the whole `<keybind key="A-Tab">...</keybind>` block.
- `A-F4` – Alt+F4 (close window). Remove that `<keybind>...</keybind>` block.
- `C-A-BackSpace` or similar – Ctrl+Alt+Backspace. Remove if present.
- Any keybind that opens a terminal (e.g. `C-A-T`) or a menu. Remove or change the key.

Example of what to remove:

```xml
<keybind key="A-Tab">
  <action name="NextWindow"/>
</keybind>
<keybind key="A-F4">
  <action name="Close"/>
</keybind>
```

Save and exit: Ctrl+O, Enter, Ctrl+X.

---

## Phase 6: raspi-config (autologin and optional overlay)

*(setup-kiosk.sh does this: `raspi-config nonint do_boot_behaviour B4` for Desktop Autologin. Use `--overlayfs` for overlay; use `--no-raspi-config` to skip.)*

### Step 6.1 – Open raspi-config

```bash
sudo raspi-config
```

### Step 6.2 – Enable Desktop Autologin

1. Go to **System Options** (or **1 System Options**).
2. Choose **Boot / Auto Login** (or **S5 Boot / Auto Login**).
3. Select **Desktop Autologin — Desktop GUI, automatically logged in as 'pi' user**.
4. Confirm and go back to the main menu.

### Step 6.3 – (Optional) Enable Overlay File System

- Only do this if you want the root filesystem to be read-only (all changes lost after reboot). Disable it when you need to update the system or the app.

1. In `raspi-config`, go to **Performance Options** (or **6 Performance Options**).
2. Choose **Overlay File System**.
3. Select **Enable**.
4. Confirm. You may be prompted to reboot later.

### Step 6.4 – Exit raspi-config

- Choose **Finish**. If asked to reboot, you can say **No** and reboot after finishing all steps below.

---

## Phase 7: (Optional) Disable desktop icons and taskbar

### Step 7.1 – List autostart entries that might start the desktop

```bash
ls -la ~/.config/autostart/ 2>/dev/null
ls -la /etc/xdg/autostart/ 2>/dev/null | head -30
```

### Step 7.2 – Disable pcmanfm desktop (if present)

If you see something like `pcmanfm-desktop.desktop` or `pcmanfm.desktop`:

```bash
mkdir -p ~/.config/autostart
# Copy to user autostart so we can override
cp /etc/xdg/autostart/pcmanfm-desktop.desktop ~/.config/autostart/ 2>/dev/null || true
```

Then edit:

```bash
nano ~/.config/autostart/pcmanfm-desktop.desktop
```

Add this line under `[Desktop Entry]`:

```ini
Hidden=true
```

Save and exit. This prevents the desktop from drawing icons. (Adjust the filename if your system uses a different one.)

### Step 7.3 – Taskbar / panel

- labwc may start a panel. To hide or minimalize it, refer to labwc documentation for your Pi OS version (e.g. theme or rc.xml). Often there is a `<core><panels>` or similar section. Making the panel empty or hidden leaves only your fullscreen app visible.

---

## Phase 8: (Optional) SSH key-only and services

*(setup-kiosk.sh can do this with `--ssh-key-only`. Ensure key login works before using.)*

### Step 8.1 – Backup sshd_config

```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
```

### Step 8.2 – Disable password authentication

```bash
sudo nano /etc/ssh/sshd_config
```

Find and set (uncomment if needed):

```
PasswordAuthentication no
ChallengeResponseAuthentication no
```

Save and exit.

### Step 8.3 – Restart SSH

```bash
sudo systemctl restart ssh
```

**Important:** Ensure you can log in with your SSH key before closing your current session. Test in another terminal: `ssh pi@<pi-ip>`.

### Step 8.4 – (Optional) Disable Bluetooth

```bash
sudo systemctl disable --now bluetooth
```

Only do this if you don’t need Bluetooth.

---

## Phase 9: Reboot and verify

### Step 9.1 – Reboot

```bash
sudo reboot
```

### Step 9.2 – After reboot

- The Pi should log in automatically as `pi` and start the Wayland/labwc session.
- labwc will run `~/.config/labwc/autostart`, which:
  - Ensures venv exists (runs `ensure_venv.sh` if needed),
  - Starts unclutter,
  - Starts `monitor.sh`,
  - Starts `iot_pubsub_gui.py --kiosk` with the venv Python.

You should see only the fullscreen IoT Pub/Sub GUI. The monitor will restart the app if it crashes.

### Step 9.3 – If the app doesn’t start

- SSH in (with your key) and check:
  - `~/.config/labwc/autostart` exists and has the right `APP_DIR`.
  - `/home/pi/iot-pubsub-gui/venv/bin/python3` exists: run `./ensure_venv.sh` again from `/home/pi/iot-pubsub-gui`.
  - Check logs: `journalctl -u graphical-session -b` or `cat /home/pi/iot-pubsub-gui/iot_pubsub_gui.log`.

---

## Quick reference: minimal command sequence

**Preferred — use [setup-kiosk.sh](setup-kiosk.sh):** Fresh Pi (key in `~/.ssh`): download to `/home/pi/setup-kiosk.sh`, then `cd /home/pi && ./setup-kiosk.sh --clone --reboot`. App already at `/home/pi/iot-pubsub-gui`: `cd /home/pi/iot-pubsub-gui && ./setup-kiosk.sh --reboot`. See "Use setup-kiosk.sh" at the top.

**Manual sequence** — if you’ve already cloned the repo to `/home/pi/iot-pubsub-gui`, this is the minimal sequence:

```bash
sudo apt-get update && sudo apt-get install -y unclutter
cd /home/pi/iot-pubsub-gui
chmod +x ensure_venv.sh monitor.sh
./ensure_venv.sh
mkdir -p ~/.config/labwc
cp /home/pi/iot-pubsub-gui/labwc-autostart.example ~/.config/labwc/autostart
chmod +x ~/.config/labwc/autostart
cp /etc/xdg/labwc/rc.xml ~/.config/labwc/rc.xml 2>/dev/null || true
nano ~/.config/labwc/rc.xml
# Remove A-Tab, A-F4 (and optionally C-A-BackSpace, terminal keybinds), save
sudo raspi-config
# Enable: Desktop Autologin; optionally Overlay FS
sudo reboot
```

After reboot, the kiosk should be running. Use this document for the detailed explanation of each step.
