# Quick Port Forwarding Guide

## What You Need to Do

**One-time setup on your router** to allow GitHub webhooks to reach your Pi.

## Step 1: Get Your Information

Run this on your Pi:
```bash
./get-webhook-info.sh
```

This shows:
- Your Pi's local IP (e.g., 192.168.1.100)
- Your router IP (e.g., 192.168.1.1)
- Your public IP (e.g., 123.45.67.89)
- Your MAC address

## Step 2: Set Static IP for Pi

**Option A: In Router (Easiest)**

1. Log into router: `http://YOUR_ROUTER_IP` (usually 192.168.1.1)
2. Find "DHCP Reservation" or "Static IP Assignment"
3. Reserve your Pi's current IP for its MAC address
4. Save

**Option B: On Pi**

1. Edit: `sudo nano /etc/dhcpcd.conf`
2. Add at end:
   ```
   interface eth0
   static ip_address=192.168.1.100/24
   static routers=192.168.1.1
   static domain_name_servers=192.168.1.1 8.8.8.8
   ```
   (Replace with your actual IPs)
3. Reboot: `sudo reboot`

## Step 3: Port Forward on Router

1. **Log into router admin:**
   - Open browser: `http://YOUR_ROUTER_IP`
   - Common defaults: `admin/admin` or `admin/password`

2. **Find Port Forwarding:**
   - May be under: Advanced → NAT → Port Forwarding
   - Or: Firewall → Port Forwarding
   - Or: Virtual Server

3. **Add New Rule:**
   - **Service Name:** GitHub Webhook (or any name)
   - **External Port:** 9000
   - **Internal IP:** Your Pi's IP (e.g., 192.168.1.100)
   - **Internal Port:** 9000
   - **Protocol:** TCP
   - **Enable:** Yes

4. **Save and Apply**

## Step 4: Get Public IP

```bash
curl ifconfig.me
```

## Step 5: Test Port Forwarding

From another device with internet:
```bash
curl http://YOUR_PUBLIC_IP:9000/health
```

Should return:
```json
{"status":"healthy","service":"iot-gui-webhook",...}
```

## Step 6: Add Webhook to GitHub

1. Go to: `https://github.com/thienanlktl/Pideployment/settings/hooks`
2. Click "Add webhook"
3. **Payload URL:** `http://YOUR_PUBLIC_IP:9000/webhook`
4. **Secret:** (from `.webhook_secret` file)
5. **Content type:** `application/json`
6. **Events:** Just the push event
7. Click "Add webhook"

## Common Router Brands

### TP-Link
- Advanced → NAT Forwarding → Virtual Servers
- Add: External Port 9000 → Internal IP:9000

### Netgear
- Advanced → Port Forwarding / Port Triggering
- Add custom service: Port 9000

### ASUS
- WAN → Virtual Server / Port Forwarding
- Add: 9000 → Pi IP:9000

### Linksys
- Connectivity → Port Forwarding
- Add: External 9000 → Internal Pi IP:9000

### D-Link
- Advanced → Port Forwarding
- Add: 9000 → Pi IP:9000

## Troubleshooting

**Port forwarding not working?**
- Check Pi has static IP
- Verify rule is enabled
- Check router firewall allows port 9000
- Test from outside network

**Public IP changed?**
- Update webhook URL in GitHub
- Or use Dynamic DNS (DuckDNS) for permanent solution

## Helper Script

For detailed step-by-step guidance:
```bash
./setup-port-forwarding.sh
```

This script:
- Detects all network information
- Provides router-specific instructions
- Tests port forwarding
- Shows exact webhook URL

