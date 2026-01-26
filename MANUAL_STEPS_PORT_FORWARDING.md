# Manual Steps Required for Port Forwarding

## Summary

After running `setup-deployment-from-scratch.sh`, you need to complete these **one-time manual steps** on your router to enable GitHub webhooks:

## Step 1: Set Static IP for Pi

**Why:** Port forwarding requires a fixed IP address. If your Pi's IP changes, port forwarding breaks.

**How:**
- **Option A (Recommended):** In router admin panel
  - Log into router: `http://YOUR_ROUTER_IP` (usually 192.168.1.1)
  - Find "DHCP Reservation" or "Static IP Assignment"
  - Reserve your Pi's current IP for its MAC address
  - Save

- **Option B:** On Pi
  - Edit: `sudo nano /etc/dhcpcd.conf`
  - Add at end:
    ```
    interface eth0
    static ip_address=YOUR_PI_IP/24
    static routers=YOUR_ROUTER_IP
    ```
  - Reboot: `sudo reboot`

**Get your info:**
```bash
./get-webhook-info.sh
```

## Step 2: Configure Port Forwarding on Router

**Why:** GitHub needs to reach your Pi from the internet. Your router blocks incoming connections by default.

**How:**
1. Log into router admin: `http://YOUR_ROUTER_IP`
2. Find "Port Forwarding" or "Virtual Server" section
3. Add new rule:
   - **Service Name:** GitHub Webhook (or any name)
   - **External Port:** 9000
   - **Internal IP:** Your Pi's IP (e.g., 192.168.1.100)
   - **Internal Port:** 9000
   - **Protocol:** TCP
   - **Enable:** Yes
4. Save and apply

**Detailed guide:**
```bash
./setup-port-forwarding.sh
```

## Step 3: Test Port Forwarding

**From another device with internet:**
```bash
curl http://YOUR_PUBLIC_IP:9000/health
```

**Should return:**
```json
{"status":"healthy","service":"iot-gui-webhook",...}
```

**Get your public IP:**
```bash
curl ifconfig.me
```

## Step 4: Add Webhook to GitHub

1. Go to: `https://github.com/thienanlktl/Pideployment/settings/hooks`
2. Click "Add webhook"
3. **Payload URL:** `http://YOUR_PUBLIC_IP:9000/webhook`
4. **Secret:** (from `.webhook_secret` file on Pi)
5. **Content type:** `application/json`
6. **Events:** Just the push event
7. Click "Add webhook"

**Get webhook info:**
```bash
./get-webhook-info.sh
```

## If Your Public IP Changes

If your ISP assigns a new public IP:

1. Get new public IP: `curl ifconfig.me`
2. Update port forwarding (if needed - usually not)
3. Update GitHub webhook URL:
   - Go to: `https://github.com/thienanlktl/Pideployment/settings/hooks`
   - Edit existing webhook
   - Update Payload URL: `http://NEW_PUBLIC_IP:9000/webhook`
   - Save

**Tip:** Consider using Dynamic DNS (DuckDNS) for a permanent domain name.

## Quick Reference

```bash
# Get all webhook information
./get-webhook-info.sh

# Detailed port forwarding guide
./setup-port-forwarding.sh

# Test webhook locally
curl http://localhost:9000/health

# Test webhook from internet (after port forwarding)
curl http://YOUR_PUBLIC_IP:9000/health
```

## Troubleshooting

**Port forwarding not working?**
- Verify Pi has static IP
- Check router rule is enabled
- Verify router firewall allows port 9000
- Test from outside network (not local network)

**Webhook not receiving events?**
- Check webhook service: `sudo systemctl status iot-gui-webhook.service`
- Check logs: `sudo journalctl -u iot-gui-webhook.service -f`
- Verify GitHub webhook shows "Recent Deliveries" with successful responses
- Test health endpoint from internet

## Need Help?

See `QUICK_PORT_FORWARDING_GUIDE.md` for detailed instructions with router-specific guidance.

