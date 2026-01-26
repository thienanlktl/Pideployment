# How GitHub Webhooks Reach Your Raspberry Pi

This guide explains how GitHub webhooks can connect to your Raspberry Pi and the different network setups.

## The Problem

GitHub webhooks need to send HTTP requests to your Pi. For this to work:
- Your Pi must be reachable from the internet
- Port 9000 must be accessible
- The webhook URL must be publicly accessible

## Network Scenarios

### Scenario 1: Pi Has Public IP (Rare)

If your Pi has a direct public IP address:
- ✅ Webhook URL: `http://YOUR_PUBLIC_IP:9000/webhook`
- ✅ Works immediately
- ⚠️ Security risk: Pi is directly exposed to internet

**Most home networks don't have this setup.**

---

### Scenario 2: Pi Behind Router/NAT (Most Common)

Most home networks have:
- Router with public IP
- Pi behind router with private IP (e.g., 192.168.1.100)
- GitHub can't directly reach the Pi

**Solutions:**

#### Option A: Port Forwarding (Recommended for Home Networks)

**How it works:**
1. Router receives webhook request on port 9000
2. Router forwards it to Pi's private IP
3. Pi receives the webhook

**Setup Steps:**

1. **Find your router's public IP:**
   ```bash
   curl ifconfig.me
   # Or visit: https://whatismyipaddress.com
   ```

2. **Configure Port Forwarding on Router:**
   - Log into router admin (usually `192.168.1.1` or `192.168.0.1`)
   - Find "Port Forwarding" or "Virtual Server" settings
   - Add rule:
     - **External Port**: 9000
     - **Internal IP**: Your Pi's IP (e.g., 192.168.1.100)
     - **Internal Port**: 9000
     - **Protocol**: TCP
   - Save and apply

3. **Set Static IP for Pi** (Important!):
   - Reserve IP in router DHCP settings
   - Or configure static IP on Pi
   - This ensures port forwarding always works

4. **Use Public IP in Webhook:**
   - Webhook URL: `http://YOUR_PUBLIC_IP:9000/webhook`
   - Example: `http://123.45.67.89:9000/webhook`

5. **Update Webhook if Public IP Changes:**
   - Most ISPs provide dynamic public IPs
   - If IP changes, update webhook URL in GitHub
   - Or use Dynamic DNS (see Option B)

**Pros:**
- ✅ Direct connection
- ✅ No third-party services
- ✅ Fast and reliable

**Cons:**
- ⚠️ Exposes Pi to internet (use firewall)
- ⚠️ Public IP may change (use Dynamic DNS)

---

#### Option B: Dynamic DNS (Best for Home Networks)

**How it works:**
1. Get a domain name that points to your router's public IP
2. Domain automatically updates when IP changes
3. Use domain name in webhook URL

**Setup Steps:**

1. **Sign up for Dynamic DNS service:**
   - **DuckDNS** (Free, recommended): https://www.duckdns.org
   - **No-IP** (Free tier available): https://www.noip.com
   - **Dynu** (Free): https://www.dynu.com

2. **Example with DuckDNS:**
   ```bash
   # Install DuckDNS updater on Pi
   sudo apt-get install curl
   
   # Create update script
   nano ~/update-duckdns.sh
   ```
   
   Add:
   ```bash
   #!/bin/bash
   echo url="https://www.duckdns.org/update?domains=YOUR_DOMAIN&token=YOUR_TOKEN&ip=" | curl -k -o ~/duckdns/duck.log -K -
   ```
   
   Make executable:
   ```bash
   chmod +x ~/update-duckdns.sh
   ```
   
   Add to crontab (update every 5 minutes):
   ```bash
   crontab -e
   # Add: */5 * * * * ~/update-duckdns.sh
   ```

3. **Configure Port Forwarding** (still needed):
   - Forward port 9000 to Pi (same as Option A)

4. **Use Domain in Webhook:**
   - Webhook URL: `http://YOUR_DOMAIN.duckdns.org:9000/webhook`
   - Example: `http://mypi.duckdns.org:9000/webhook`

**Pros:**
- ✅ Works even if public IP changes
- ✅ Easy to remember domain name
- ✅ Free services available

**Cons:**
- ⚠️ Still need port forwarding
- ⚠️ Domain updates may have delay

---

#### Option C: ngrok (Best for Testing/Development)

**How it works:**
1. ngrok creates a tunnel from internet to your Pi
2. Provides a public HTTPS URL
3. No port forwarding needed

**Setup Steps:**

1. **Install ngrok:**
   ```bash
   # Download ngrok for ARM
   wget https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz
   tar xvzf ngrok-v3-stable-linux-arm.tgz
   sudo mv ngrok /usr/local/bin/
   ```

2. **Start ngrok tunnel:**
   ```bash
   ngrok http 9000
   ```
   
   This will show:
   ```
   Forwarding: https://abc123.ngrok.io -> http://localhost:9000
   ```

3. **Use ngrok URL in Webhook:**
   - Webhook URL: `https://abc123.ngrok.io/webhook`
   - Use HTTPS (ngrok provides SSL)

4. **Make ngrok persistent (optional):**
   ```bash
   # Create systemd service for ngrok
   sudo nano /etc/systemd/system/ngrok.service
   ```
   
   Add:
   ```ini
   [Unit]
   Description=ngrok tunnel
   After=network.target
   
   [Service]
   Type=simple
   User=pi
   ExecStart=/usr/local/bin/ngrok http 9000
   Restart=always
   
   [Install]
   WantedBy=multi-user.target
   ```
   
   Enable:
   ```bash
   sudo systemctl enable ngrok.service
   sudo systemctl start ngrok.service
   ```

**Pros:**
- ✅ No port forwarding needed
- ✅ HTTPS included
- ✅ Works behind any firewall
- ✅ Great for testing

**Cons:**
- ⚠️ Free tier URLs change on restart
- ⚠️ Requires ngrok account for static URLs
- ⚠️ Third-party dependency

---

#### Option D: Cloudflare Tunnel (Advanced)

**How it works:**
- Cloudflare creates secure tunnel
- No port forwarding needed
- Free and reliable

**Setup:**
- More complex setup
- Requires Cloudflare account
- See: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/

---

## Recommended Setup for Home Network

**Best combination:**
1. ✅ **Set static IP** for Pi on router
2. ✅ **Port forward** port 9000 to Pi
3. ✅ **Use Dynamic DNS** (DuckDNS) for domain name
4. ✅ **Configure firewall** on Pi (allow only port 9000)

**Webhook URL:**
```
http://mypi.duckdns.org:9000/webhook
```

---

## Security Considerations

### 1. Firewall Configuration

**On Pi (UFW):**
```bash
# Allow only port 9000 from internet
sudo ufw allow 9000/tcp
sudo ufw enable
```

**On Router:**
- Only forward port 9000
- Don't expose other ports unnecessarily

### 2. Webhook Secret

- ✅ Always use strong webhook secret
- ✅ Secret is verified by webhook listener
- ✅ Prevents unauthorized access

### 3. Restrict Access (Advanced)

You can restrict webhook to GitHub IPs only:
```bash
# Get GitHub webhook IP ranges
# https://api.github.com/meta

# Configure firewall to allow only GitHub IPs
sudo ufw allow from 140.82.112.0/20 to any port 9000
```

---

## Testing Webhook Connectivity

### Test 1: From Pi (Local)
```bash
curl http://localhost:9000/health
```

### Test 2: From Another Device on Same Network
```bash
curl http://192.168.1.100:9000/health
```

### Test 3: From Internet
```bash
# From any computer with internet
curl http://YOUR_PUBLIC_IP:9000/health
# Or
curl http://YOUR_DOMAIN.duckdns.org:9000/health
```

### Test 4: GitHub Webhook Test
- Go to GitHub webhook settings
- Click on your webhook
- Click "Recent Deliveries"
- Click on a delivery to see response
- Should show "200 OK"

---

## Troubleshooting

### Webhook Not Receiving Events

**Check 1: Port Forwarding**
```bash
# Check if port is forwarded correctly
# Test from outside network
curl http://YOUR_PUBLIC_IP:9000/health
```

**Check 2: Firewall**
```bash
# Check UFW status
sudo ufw status

# Check if port is listening
sudo netstat -tuln | grep 9000
# Or
sudo ss -tuln | grep 9000
```

**Check 3: Webhook Service**
```bash
sudo systemctl status iot-gui-webhook.service
```

**Check 4: Router Configuration**
- Verify port forwarding rule
- Check if Pi has static IP
- Verify router firewall allows port 9000

### Public IP Changed

**Solution 1: Update Webhook URL**
```bash
# Get new public IP
curl ifconfig.me

# Update webhook in GitHub with new IP
```

**Solution 2: Use Dynamic DNS**
- Set up DuckDNS or similar
- Domain automatically updates
- No manual updates needed

---

## Quick Setup Guide

### For Most Users (Home Network)

1. **Set static IP for Pi** (in router or Pi config)
2. **Port forward 9000** on router to Pi's IP
3. **Set up DuckDNS** (free, 5 minutes)
4. **Use DuckDNS domain** in webhook URL
5. **Done!** Webhook will work permanently

### For Testing/Development

1. **Use ngrok:**
   ```bash
   ngrok http 9000
   ```
2. **Copy HTTPS URL** to webhook
3. **Done!** Works immediately

---

## Summary

**GitHub webhooks reach your Pi by:**
1. Sending HTTP request to webhook URL
2. Request goes through internet to your router's public IP
3. Router forwards to Pi (via port forwarding)
4. Pi's webhook listener receives and processes it

**You need:**
- ✅ Pi accessible from internet (port forwarding or tunnel)
- ✅ Port 9000 open and forwarded
- ✅ Webhook URL pointing to accessible address
- ✅ Webhook secret for security

**Best solution:**
- Static IP + Port Forwarding + Dynamic DNS = Permanent solution

