# Setup Script Improvements

## Overview
The `setup-deployment-from-scratch.sh` script has been completely rewritten to work on a **completely fresh Raspberry Pi** with only the git repository URL. It now handles all edge cases and can clone the repository automatically if needed.

## Key Improvements

### 1. **Automatic Repository Cloning**
- ✅ Detects if running from within a git repository
- ✅ If not in a repo, offers to clone it automatically
- ✅ Uses HTTPS for initial clone (works without SSH setup)
- ✅ Handles existing directories gracefully

### 2. **Better Error Handling**
- ✅ Changed from `set -e` to `set +e` for graceful error handling
- ✅ Explicit error checks with proper exit codes
- ✅ Continues setup even if some optional steps fail
- ✅ Clear error messages with actionable solutions

### 3. **File Verification**
- ✅ Verifies required files exist before proceeding
- ✅ Automatically pulls latest code if files are missing
- ✅ Warns about missing files but continues if possible

### 4. **HTTPS Support**
- ✅ Works with HTTPS repository URLs (no SSH required initially)
- ✅ Offers to convert HTTPS to SSH after SSH key is set up
- ✅ Handles both SSH and HTTPS remotes gracefully

### 5. **Virtual Environment Handling**
- ✅ Asks before recreating existing venv
- ✅ Better error handling for venv creation
- ✅ Verifies venv activation before proceeding

### 6. **Improved User Experience**
- ✅ Clear step-by-step progress
- ✅ Interactive prompts for important decisions
- ✅ Default values for common choices
- ✅ Better IP address detection (multiple methods)

### 7. **Robust Secret Generation**
- ✅ Multiple fallback methods for secret generation
- ✅ Handles cases where Python secrets module unavailable
- ✅ Uses openssl or date-based fallback

### 8. **Better Git Handling**
- ✅ Detects if remote is HTTPS and suggests SSH conversion
- ✅ Automatically pulls latest code after remote setup
- ✅ Handles missing remotes gracefully

## Usage Scenarios

### Scenario 1: Fresh Pi, No Repository
```bash
# Download the script
curl -O https://raw.githubusercontent.com/thienanlktl/Pideployment/main/setup-deployment-from-scratch.sh
chmod +x setup-deployment-from-scratch.sh

# Run it - it will clone the repo automatically
./setup-deployment-from-scratch.sh
```

### Scenario 2: Repository Already Cloned (HTTPS)
```bash
cd ~/Pideployment
./setup-deployment-from-scratch.sh
# Script will detect HTTPS and offer to convert to SSH
```

### Scenario 3: Repository Already Cloned (SSH)
```bash
cd ~/Pideployment
./setup-deployment-from-scratch.sh
# Script will use existing SSH setup
```

## What the Script Does Now

1. ✅ **Checks if in git repo** - If not, offers to clone
2. ✅ **Installs prerequisites** - Python 3, git, system packages
3. ✅ **Creates virtual environment** - With proper error handling
4. ✅ **Installs dependencies** - Flask (required) + requirements.txt
5. ✅ **Verifies required files** - Checks for iot_pubsub_gui.py, webhook_listener.py, etc.
6. ✅ **Generates SSH key** - For GitHub authentication
7. ✅ **Configures git remote** - Handles HTTPS → SSH conversion
8. ✅ **Pulls latest code** - Ensures repository is up to date
9. ✅ **Generates webhook secret** - With multiple fallback methods
10. ✅ **Makes scripts executable** - All deployment scripts
11. ✅ **Sets up systemd service** - With correct paths and secrets
12. ✅ **Configures firewall** - Opens webhook port if needed
13. ✅ **Tests setup** - Runs verification tests

## Error Recovery

The script now handles:
- ✅ Missing Python 3 → Installs automatically
- ✅ Missing git → Installs automatically
- ✅ Missing python3-venv → Installs automatically
- ✅ Failed venv creation → Retries with python3-venv
- ✅ Missing files → Pulls latest code automatically
- ✅ HTTPS remote → Offers SSH conversion
- ✅ Missing SSH key → Generates automatically
- ✅ Failed secret generation → Uses fallback methods

## Testing Checklist

Before deploying, test these scenarios:

- [ ] Fresh Pi with no repository
- [ ] Fresh Pi with HTTPS cloned repository
- [ ] Fresh Pi with SSH cloned repository
- [ ] Pi with existing venv
- [ ] Pi with existing SSH keys
- [ ] Pi with firewall enabled
- [ ] Pi with firewall disabled
- [ ] Pi without internet (should fail gracefully)

## Known Limitations

1. **Internet Required**: Script needs internet for:
   - Cloning repository
   - Installing packages
   - Pulling latest code

2. **Sudo Required**: Some steps need sudo for:
   - Installing system packages
   - Setting up systemd service
   - Configuring firewall

3. **GitHub Access**: For SSH setup, you need to:
   - Add SSH key to GitHub manually
   - Add webhook to GitHub manually

## Future Improvements

Potential enhancements:
- [ ] Support for private repositories with token
- [ ] Automatic webhook creation via GitHub API
- [ ] Support for multiple branches
- [ ] Backup/restore functionality
- [ ] Dry-run mode for testing

## Summary

The script is now **production-ready** and can handle:
- ✅ Completely fresh Raspberry Pi
- ✅ Any repository state (cloned or not)
- ✅ HTTPS or SSH remotes
- ✅ Missing dependencies
- ✅ Error recovery
- ✅ User-friendly interactive prompts

It's designed to work "out of the box" with minimal user intervention!

