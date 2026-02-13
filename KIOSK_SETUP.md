# Raspberry Pi Kiosk Setup (Wayland / labwc)

Turn a Raspberry Pi running **Raspberry Pi OS 64-bit Bookworm+** with **Wayland** and **labwc** into a locked-down kiosk that boots only into `iot_pubsub_gui.py`: fullscreen, no taskbar, no escape keys, optional cursor hide, and auto-restart on crash.

**For a detailed, step-by-step manual checklist**, see **[KIOSK_MANUAL_STEPS.md](KIOSK_MANUAL_STEPS.md)** — every command and action to run, in order.

**To run all steps automatically (one script):** use **[setup-kiosk.sh](setup-kiosk.sh)** — see "How to apply setup-kiosk.sh" and "One-shot script" below.

---

## How to apply setup-kiosk.sh

### Fresh machine (no code yet): clone via SSH using existing keys in `~/.ssh`

Use this when the Pi is new and you want the script to **pull the code** using the SSH key already in `~/.ssh` (e.g. you copied your private key to the Pi or generated one and added the public key to GitHub).

1. **Ensure SSH keys are on the Pi** (one of these):
   - **Copy from another machine:** copy your existing `id_ed25519` and `id_ed25519.pub` (or `id_rsa` / `id_rsa.pub`) into `/home/pi/.ssh/` and run `chmod 600 /home/pi/.ssh/id_ed25519`.
   - **Or generate on the Pi:** run `ssh-keygen -t ed25519 -N "" -f /home/pi/.ssh/id_ed25519`, then add the contents of `/home/pi/.ssh/id_ed25519.pub` to GitHub (Settings → SSH and GPG keys → New SSH key).

2. **Get the setup script onto the Pi** (do **not** put it inside the app directory — `--clone` will create the app directory). For example:
   - **Option A — One-line download** (run on the Pi):
     ```bash
     curl -sL https://raw.githubusercontent.com/thienanlktl/Pideployment/main/setup-kiosk.sh -o /home/pi/setup-kiosk.sh
     chmod +x /home/pi/setup-kiosk.sh
     ```
   - **Option B:** Copy `setup-kiosk.sh` via USB/SCP to `/home/pi/setup-kiosk.sh` and `chmod +x` it.

3. **Run the script with `--clone`** so it clones the repo via SSH (using `~/.ssh`) into `/home/pi/iot-pubsub-gui` and then does the rest:
   ```bash
   cd /home/pi
   ./setup-kiosk.sh --clone --reboot
   ```
   The script clones `git@github.com:thienanlktl/Pideployment.git` (SSH) into `/home/pi/iot-pubsub-gui`, then installs packages, venv, labwc autostart, rc.xml, and raspi-config autologin. With `--reboot` it reboots at the end.

   For a **private** repo, your GitHub account must have access and the **public** key in `~/.ssh` must be added to that account (or to a deploy key for the repo).

4. **If you don't have an SSH key on the Pi** and the repo is **public**, use HTTPS instead:
   ```bash
   ./setup-kiosk.sh --clone-https --reboot
   ```

### Machine that already has the app code

If the project is already at `/home/pi/iot-pubsub-gui` (e.g. you cloned or copied it yourself), run the script **without** `--clone`:

```bash
cd /home/pi/iot-pubsub-gui
chmod +x setup-kiosk.sh
./setup-kiosk.sh --reboot
```

---

## One-shot script (setup-kiosk.sh)

Run all kiosk steps in one go. Use `--clone` on a fresh machine so the script pulls the code via SSH from `~/.ssh`; otherwise the app directory must already exist.

**Options:**

- `--app-dir DIR` — App directory (default: `/home/pi/iot-pubsub-gui`).
- `--clone` — Clone repo into `--app-dir` using **SSH** (uses existing keys in `~/.ssh`). Requires public key added to GitHub/GitLab.
- `--clone-https` — Same as `--clone` but use HTTPS (no SSH key; use for public repo).
- `--no-raspi-config` — Skip autologin / raspi-config.
- `--no-rcxml` — Skip editing labwc rc.xml (you can edit it manually later).
- `--overlayfs` — Enable overlay file system (read-only root).
- `--ssh-key-only` — Disable SSH password authentication (ensure key login works first).
- `--reboot` — Reboot at the end.

**Examples:**

```bash
# Fresh Pi: clone via SSH (key in ~/.ssh) then setup and reboot
./setup-kiosk.sh --clone --reboot

# Fresh Pi: clone via HTTPS (no key needed, public repo)
./setup-kiosk.sh --clone-https --reboot

# App already present: setup and reboot
./setup-kiosk.sh --reboot

# Custom path, no reboot
./setup-kiosk.sh --app-dir /home/pi/my-kiosk
# then: sudo reboot
```

---

## Plan (10 steps)

| Step | What |
|------|------|
| 1 | **Application** – Modify `iot_pubsub_gui.py`: fullscreen on launch, disable exit keys (Escape, Alt+F4, Ctrl+Q, etc.), optional idle cursor hide, `--kiosk` flag. |
| 2 | **Monitor script** – Add `monitor.sh` to check every 5–10s and restart the Python app if it exits. |
| 3 | **labwc autostart** – Create `~/.config/labwc/autostart` to run unclutter, monitor, and the app (no desktop, no taskbar). |
| 4 | **labwc rc.xml** – Disable system shortcuts (Alt+Tab, etc.) so the user cannot leave the app. |
| 5 | **Autologin** – Use `raspi-config` to enable Desktop Autologin for user `pi`. |
| 6 | **Overlay FS** – Enable Overlay File System (read-only root) for protection. |
| 7 | **No desktop / taskbar** – Disable `pcmanfm --desktop` and hide or remove taskbar/panels. |
| 8 | **SSH & services** – SSH key-only (disable password auth), disable unnecessary services. |
| 9 | **Physical** – Optional: cover USB ports to prevent keyboard/mouse. |
| 10 | **Deploy** – Copy app + scripts to `/home/pi/iot-pubsub-gui`, run `ensure_venv.sh` (creates venv + installs all packages), then run commands below. |

---

## 1. Application changes (`iot_pubsub_gui.py`)

- **Fullscreen:** Already starts fullscreen unless `--no-fullscreen`. In kiosk mode we always use fullscreen.
- **Exit keys disabled:** When `--kiosk` is passed:
  - Escape, Alt+F4, Ctrl+Q, Ctrl+W, Ctrl+Alt+Backspace (and similar) are caught and do nothing.
  - `closeEvent` is ignored so the window cannot be closed.
- **Fullscreen button:** Hidden in kiosk mode.
- **Cursor:** Optional in-app idle cursor hide; otherwise use `unclutter -idle 0.1` from autostart.

See the code edits in this repo (search for `kiosk_mode` and `keyPressEvent`).

---

## 2. Ensure venv and all packages (`ensure_venv.sh`)

- **Location:** Same directory as the app (e.g. `/home/pi/iot-pubsub-gui/ensure_venv.sh`).
- **Purpose:** Creates the virtual environment if missing, runs `pip install -r requirements.txt`, and verifies every required import (PyQt6, awscrt, awsiot, cryptography, dateutil, requests, git). Safe to run multiple times.
- **Usage:** `./ensure_venv.sh` or `bash ensure_venv.sh` from the app directory. The app **requires** running with this venv when it exists (see `check_dependencies()` in `iot_pubsub_gui.py`).
- **Kiosk:** Autostart and `monitor.sh` run this when venv is missing so the first boot or after a fresh clone can self-install.

## 3. Monitor script (`monitor.sh`)

Location: `/home/pi/iot-pubsub-gui/monitor.sh` (or same directory as the app).

- If venv does not exist, runs `ensure_venv.sh` first, then starts the loop.
- Uses **venv** Python only: `$APP_DIR/venv/bin/python3` and `$APP_DIR/iot_pubsub_gui.py --kiosk`.
- Loop: every 10s checks if the app process is running; if not, restarts it.

- Run this from autostart **after** unclutter and **before** the first launch of the app (or start the app once and let the monitor only restart it when it dies).

---

## 4. labwc autostart

**File:** `~/.config/labwc/autostart`

Create directory if needed. Use the content from `labwc-autostart.example` in this repo; it:

- Ensures venv and all packages (runs `ensure_venv.sh` if venv is missing).
- Starts unclutter, then `monitor.sh`, then the app with **venv** Python.

```bash
mkdir -p ~/.config/labwc
cp /home/pi/iot-pubsub-gui/labwc-autostart.example ~/.config/labwc/autostart
```

- Adjust `APP_DIR` in the file if your app is not in `/home/pi/iot-pubsub-gui`.
- The app is always started with `$APP_DIR/venv/bin/python3` so all packages from the venv are used.

---

## 5. labwc rc.xml (disable shortcuts)

- **System config:** `/etc/xdg/labwc/rc.xml`
- **User override:** `~/.config/labwc/rc.xml`

To avoid breaking system updates, create a **user** override and only override keybindings:

```bash
mkdir -p ~/.config/labwc
```

Copy the default rc.xml so you have a full file, then edit keybindings:

```bash
# If no user rc.xml exists, copy from system default
cp /etc/xdg/labwc/rc.xml ~/.config/labwc/rc.xml 2>/dev/null || true
```

Edit `~/.config/labwc/rc.xml` and in the `<keyboard>` section remove or comment out bindings you want to disable, for example:

- `A-Tab` (Alt+Tab) – cycle windows  
- `A-F4` (Alt+F4) – close window  
- `C-A-BackSpace` – often “restart compositor”  
- Any binding that opens a terminal (e.g. `C-A-T`) or menu

Example: to disable Alt+Tab and Alt+F4, find lines like:

```xml
<keybind key="A-Tab">
  <action name="NextWindow"/>
</keybind>
<keybind key="A-F4">
  <action name="Close"/>
</keybind>
```

Remove those `<keybind>...</keybind>` blocks or change the key to something harmless. Restart labwc or re-login for changes to apply.

---

## 6. raspi-config: Autologin

```bash
sudo raspi-config
```

- **System Options** → **Boot / Auto Login** → **Desktop Autologin** (user `pi`).

So the Pi boots straight to the desktop (labwc), and labwc autostart then runs only your app + unclutter + monitor.

---

## 7. Overlay File System (read-only root)

```bash
sudo raspi-config
```

- **Performance Options** → **Overlay File System** → **Enable** → Reboot when prompted.

This makes the root filesystem read-only; any change after reboot is lost. Disable it when you need to perform system or app updates.

---

## 8. No desktop icons / no taskbar

- **Disable desktop (pcmanfm):** If the session starts `pcmanfm --desktop`, disable it (e.g. remove or edit the autostart that launches it, or disable from desktop preferences). On Pi OS with labwc, check:
  - `~/.config/autostart/`
  - `/etc/xdg/autostart/`
  Remove or set `Hidden=true` for `pcmanfm-desktop.desktop` (or equivalent) so the desktop is not drawn.
- **Taskbar / panel:** labwc may start a panel or tray. Configure labwc (e.g. in `rc.xml` or labwc docs) to not show a panel, or use a minimal panel with no window list or menu. That way the user only sees your fullscreen app.

---

## 9. SSH and services

- **SSH key-only (disable password):**

  Edit `/etc/ssh/sshd_config`:

  ```bash
  sudo nano /etc/ssh/sshd_config
  ```

  Set:

  ```
  PasswordAuthentication no
  ChallengeResponseAuthentication no
  ```

  Restart SSH:

  ```bash
  sudo systemctl restart ssh
  ```

- **Disable services you don’t need:** e.g. Bluetooth, unused networking, or other daemons:

  ```bash
  sudo systemctl disable --now bluetooth   # example
  ```

  Only disable what you are sure you don’t need.

---

## 10. Physical protection

- Cover or lock USB ports so users cannot plug in a keyboard/mouse (optional, for high-security kiosks).
- Keep the Pi in a locked enclosure if needed.

---

## 11. Exact commands (copy-paste)

Assume the app lives in `/home/pi/iot-pubsub-gui` and you’ve already cloned/copied the repo and created the venv.

```bash
# 1) Install unclutter (cursor hide)
sudo apt-get update
sudo apt-get install -y unclutter

# 2) App directory: ensure venv and ALL packages from requirements.txt
APP_DIR="/home/pi/iot-pubsub-gui"
cd "$APP_DIR" || exit 1
chmod +x ensure_venv.sh monitor.sh
./ensure_venv.sh

# 3) labwc autostart (uses venv and ensure_venv when venv missing)
mkdir -p ~/.config/labwc
cp "$APP_DIR/labwc-autostart.example" ~/.config/labwc/autostart

# 4) Optional: user labwc rc.xml to disable Alt+Tab etc.
cp /etc/xdg/labwc/rc.xml ~/.config/labwc/rc.xml 2>/dev/null || true
nano ~/.config/labwc/rc.xml
# Remove or change keybindings for A-Tab, A-F4, C-A-BackSpace, terminal, etc.

# 5) raspi-config (interactive)
sudo raspi-config
# Enable: Desktop Autologin, then optionally Overlay FS

# 6) SSH key-only (optional, ensure key login works first)
sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart ssh
```

After reboot, the Pi should autologin to the desktop and labwc autostart will run unclutter, the monitor, and your app in kiosk mode. The monitor will restart the app every 10s if it crashes.

---

## Compatibility

- **Raspberry Pi 4/5**, **Raspberry Pi OS 64-bit Bookworm (or newer)**, **Wayland** with **labwc**.
- Not for legacy X11/LXDE or Wayfire; adjust paths and WM-specific steps if you use another session.

---

## MQTT / pip

All dependencies (PyQt6, awsiotsdk, awscrt, cryptography, requests, GitPython, etc.) are installed in the project venv via `ensure_venv.sh` or `pip install -r requirements.txt`. The app checks that every required package is installed and that you run with the project venv when it exists.
