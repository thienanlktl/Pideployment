# Manual Steps Summary

This document lists **only the manual steps** you need to do. Everything else is automated.

## One-Time Manual Steps

### 1. Add SSH Key to GitHub (One-Time)

**When**: After running `setup-deployment-from-scratch.sh`

**Steps**:
1. Copy the SSH public key shown by the script
2. Go to: `https://github.com/thienanlktl/Pideployment/settings/keys`
3. Click "Add deploy key"
4. Paste the public key
5. Click "Add key"

**Note**: This is permanent - the key doesn't change.

---

### 2. Create GitHub Webhook (One-Time Setup)

**When**: After running `setup-deployment-from-scratch.sh`

**Steps**:
1. Get webhook information:
   ```bash
   ./get-webhook-info.sh
   ```
   This shows:
   - Current IP address
   - Webhook secret
   - Exact webhook URL

2. Go to: `https://github.com/thienanlktl/Pideployment/settings/hooks`

3. Click "Add webhook"

4. Fill in:
   - **Payload URL**: `http://YOUR_PI_IP:9000/webhook` (from script output)
   - **Content type**: `application/json`
   - **Secret**: (from `.webhook_secret` file or script output)
   - **Events**: Just the push event
   - **Active**: ✓

5. Click "Add webhook"

**Note**: 
- Secret is saved in `.webhook_secret` file - it doesn't change
- IP address may change on reboot - see below

---

## After Reboot (If IP Changed)

### Update Webhook URL in GitHub

**When**: After Pi reboot, if IP address changed

**Steps**:
1. Get new IP and webhook info:
   ```bash
   ./get-webhook-info.sh
   ```

2. Go to: `https://github.com/thienanlktl/Pideployment/settings/hooks`

3. Click on your existing webhook

4. Click "Edit"

5. Update **Payload URL** with new IP:
   - Old: `http://192.168.1.100:9000/webhook`
   - New: `http://192.168.1.105:9000/webhook` (example)

6. Click "Update webhook"

**Note**: 
- Secret stays the same - no need to change it
- Only the IP address in the URL changes

---

## Avoid Manual Updates: Set Static IP

To avoid updating the webhook URL after every reboot, set a static IP:

### Option 1: Router Configuration (Easiest)

1. Find your Pi's MAC address:
   ```bash
   ip link show | grep -A 1 "state UP" | grep "link/ether"
   ```

2. Log into your router admin panel

3. Find "DHCP Reservation" or "Static IP Assignment"

4. Reserve an IP for your Pi's MAC address
   - Example: Reserve `192.168.1.100` for Pi's MAC

5. Reboot Pi - it will always get the same IP

### Option 2: Pi Configuration

Edit `/etc/dhcpcd.conf`:
```bash
sudo nano /etc/dhcpcd.conf
```

Add at the end:
```
interface eth0
static ip_address=192.168.1.100/24
static routers=192.168.1.1
static domain_name_servers=192.168.1.1 8.8.8.8
```

Replace:
- `192.168.1.100` with your desired IP
- `192.168.1.1` with your router IP
- `eth0` with `wlan0` if using WiFi

Reboot:
```bash
sudo reboot
```

---

## Quick Reference

### Get Webhook Info Anytime
```bash
./get-webhook-info.sh
```

### Check Current IP
```bash
hostname -I
```

### Check Webhook Secret
```bash
cat .webhook_secret
```

### GitHub URLs
- **Deploy Keys**: `https://github.com/thienanlktl/Pideployment/settings/keys`
- **Webhooks**: `https://github.com/thienanlktl/Pideployment/settings/hooks`

---

## Summary

**One-Time Setup**:
1. ✅ Add SSH key to GitHub (permanent)
2. ✅ Create webhook in GitHub (secret is permanent, IP may change)

**After Reboot** (if IP changed):
1. ✅ Update webhook URL in GitHub with new IP

**To Avoid Manual Updates**:
- ✅ Set static IP on router or Pi

That's it! Only 2-3 manual steps total, and the IP update is only needed if you don't set a static IP.

