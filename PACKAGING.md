# Packaging IoT PubSub GUI for Raspberry Pi

This guide explains how to build an **installable package** (.deb) so users can download it from the internet and install it on Raspberry Pi like other applications.

---

## Overview

| Method | Output | User experience |
|--------|--------|------------------|
| **.deb package** | `iot-pubsub-gui_1.0.7_armhf.deb` | Download → double-click or `sudo dpkg -i ...deb` → appears in menu |
| **Release tarball + install.sh** | `iot-pubsub-gui-1.0.7.tar.gz` | Download → extract → run `./install.sh` (no git needed) |

---

## Option 1: Build and publish a .deb package (recommended)

### Step 1: Build the .deb on a Raspberry Pi (or Debian/Ubuntu)

On the Pi (or any Debian/Ubuntu machine with the repo cloned):

```bash
cd /path/to/Pideployment
chmod +x build-deb.sh
./build-deb.sh
```

This creates a file like: **`iot-pubsub-gui_1.0.7_armhf.deb`** (or `_arm64.deb` on 64-bit Pi OS, `_amd64.deb` on Ubuntu PC).

- **32-bit Raspberry Pi OS** → build on a 32-bit Pi → `_armhf.deb`.
- **64-bit Raspberry Pi OS** → build on a 64-bit Pi → `_arm64.deb`.
- Build on the **same architecture** as the target (or use a Pi to build for Pi).
- To build for Pi from an x86 PC you need a chroot or VM with Debian armhf/arm64 (advanced).

### Step 2: Upload the .deb to GitHub Releases

1. On GitHub: **Releases** → **Draft a new release**.
2. **Tag**: e.g. `v1.0.7` (match your VERSION file).
3. **Title**: e.g. `Release 1.0.7`.
4. **Attach** the `.deb` file (and optionally the tarball from Option 2).
5. Publish the release.

Example download URL:  
`https://github.com/thienanlktl/Pideployment/releases/download/v1.0.7/iot-pubsub-gui_1.0.7_armhf.deb`

### Step 3: User installs on Raspberry Pi

User downloads the .deb (browser or `wget`), then:

```bash
sudo apt install -f ./iot-pubsub-gui_1.0.7_armhf.deb
# or
sudo dpkg -i ./iot-pubsub-gui_1.0.7_armhf.deb
sudo apt install -f   # fix dependencies if needed
```

Or: double-click the .deb in the file manager (Raspberry Pi OS will offer to install).

After install, the app appears in the **application menu** as "IoT PubSub GUI". No desktop icon is added by the package; user can add it from the menu (right‑click → Add to Desktop) or run once:  
`cp /usr/share/applications/iot-pubsub-gui.desktop ~/Desktop/`

---

## Option 2: Release tarball (download and run install.sh)

For users who prefer “download archive and run installer” (no .deb):

### Step 1: Create a tarball

On the Pi or any machine (from the repo root):

```bash
VERSION=$(cat VERSION)
git archive --format=tar.gz --prefix=iot-pubsub-gui-"$VERSION"/ HEAD > "iot-pubsub-gui-${VERSION}.tar.gz"
```

Or zip:

```bash
VERSION=$(cat VERSION)
git archive --format=zip --prefix=iot-pubsub-gui-"$VERSION"/ HEAD > "iot-pubsub-gui-${VERSION}.zip"
```

### Step 2: Upload to GitHub Releases

Attach `iot-pubsub-gui-1.0.7.tar.gz` (or .zip) to the same release as the .deb.

### Step 3: User installs

```bash
wget https://github.com/thienanlktl/Pideployment/releases/download/v1.0.7/iot-pubsub-gui-1.0.7.tar.gz
tar xzf iot-pubsub-gui-1.0.7.tar.gz
cd iot-pubsub-gui-1.0.7
bash install.sh
```

Install script will install into `~/iot-pubsub-gui` (or `IOT_INSTALL_DIR`). For a tarball install, you may want an install mode that uses the current directory instead of cloning from git (e.g. `IOT_INSTALL_DIR=. bash install.sh` from inside the extracted folder and adjust install.sh to skip clone when run from a release tarball). Currently install.sh clones from git; for tarball-only install you’d either copy files to a target dir and run venv/desktop steps, or add a “install from this directory” path in install.sh.

---

## Quick reference: one-time packaging checklist

1. Update **VERSION** and commit.
2. On a Raspberry Pi (or Debian/Ubuntu): **`./build-deb.sh`**.
3. Create a **GitHub Release** with tag `v$(cat VERSION)`.
4. **Upload** the generated `.deb` (and optionally the tarball) to that release.
5. In **README** or docs, add the **download link** and install commands above.

---

## Files added for packaging

| File | Purpose |
|------|--------|
| `build-deb.sh` | Builds the .deb from the repo (run on Pi or Debian/Ubuntu). |
| `PACKAGING.md` | This guide. |

The .deb installs the app under **/opt/iot-pubsub-gui**, creates a venv in postinst, and registers the app in the system application menu.
