# GitHub Webhook Setup - Step by Step

## Quick Answer

**Yes, you need to manually create the webhook on GitHub.** The script cannot do this automatically, but it makes it very easy by providing all the information you need.

## Why Manual?

GitHub webhooks must be created through GitHub's web interface or API. The script cannot automatically create them because:
- It requires GitHub authentication (OAuth or Personal Access Token)
- It needs repository admin permissions
- It's a one-time setup that's easy to do manually

## What the Script Provides

The `setup-deployment-from-scratch.sh` script automatically:
- ✅ Generates a secure webhook secret
- ✅ Detects your Pi's IP address
- ✅ Shows you the exact webhook URL
- ✅ Displays all information needed

You just need to copy and paste it into GitHub!

## Step-by-Step Webhook Setup

### Step 1: Run Setup Script

```bash
./setup-deployment-from-scratch.sh
```

At the end, you'll see output like:

```
GitHub Webhook Configuration:
  URL: http://192.168.1.100:9000/webhook
  Secret: abc123xyz789...
  Content type: application/json
  Events: Just the push event

GitHub Webhook Setup URL:
  https://github.com/thienanlktl/Pideployment/settings/hooks
```

### Step 2: Go to GitHub Webhook Settings

1. Open your browser
2. Go to: `https://github.com/thienanlktl/Pideployment/settings/hooks`
   - (Replace `thienanlktl/Pideployment` with your repository)
3. Or navigate: Repository → Settings → Webhooks

### Step 3: Create Webhook

1. Click **"Add webhook"** button

2. Fill in the form:

   **Payload URL:**
   ```
   http://YOUR_PI_IP:9000/webhook
   ```
   - Replace `YOUR_PI_IP` with the IP from script output
   - Example: `http://192.168.1.100:9000/webhook`

   **Content type:**
   - Select: `application/json`

   **Secret:**
   - Paste the secret from script output
   - Example: `abc123xyz789...`

   **Which events would you like to trigger this webhook?**
   - Select: **"Just the push event"**

   **Active:**
   - Checked ✓

3. Click **"Add webhook"**

### Step 4: Verify Webhook

After creating the webhook:

1. GitHub will send a test ping
2. Check the **"Recent Deliveries"** tab
3. You should see a green checkmark ✓
4. If there's an error, check:
   - Is your Pi's IP address correct?
   - Is port 9000 open in firewall?
   - Is the webhook service running?

## Testing the Webhook

### Test 1: GitHub Test Ping

After creating the webhook, GitHub automatically sends a test ping. Check:
- **GitHub**: Webhook → Recent Deliveries → Should show "200 OK"
- **Pi**: `sudo journalctl -u iot-gui-webhook.service -n 20`

### Test 2: Manual Test

```bash
# On your Pi, test the webhook endpoint
curl http://localhost:9000/health
```

Should return:
```json
{
  "status": "healthy",
  "service": "iot-gui-webhook",
  ...
}
```

### Test 3: Real Push Test

1. Make a small change to any file
2. Commit and push:
   ```bash
   git add .
   git commit -m "Test webhook"
   git push origin main
   ```
3. Watch the logs:
   ```bash
   # Webhook received
   sudo journalctl -u iot-gui-webhook.service -f
   
   # Update process
   tail -f update.log
   
   # Application restart
   tail -f logs/app.log
   ```

## Troubleshooting Webhook Setup

### Webhook Not Receiving Events

**Check 1: Webhook Service Running**
```bash
sudo systemctl status iot-gui-webhook.service
```

**Check 2: Port 9000 Open**
```bash
sudo ufw status
# If firewall is active, make sure port 9000 is allowed
```

**Check 3: GitHub Webhook Delivery**
- Go to: Repository → Settings → Webhooks
- Click on your webhook
- Check "Recent Deliveries" tab
- Look for error messages

**Check 4: IP Address**
- Make sure the IP in webhook URL is correct
- Find your IP: `hostname -I`
- If behind NAT, you may need port forwarding or ngrok

### Common Errors

**"Invalid signature"**
- Secret doesn't match
- Check secret in GitHub matches the one in `.webhook_secret` file

**"Connection refused"**
- Webhook service not running
- Port 9000 not open
- Wrong IP address

**"Timeout"**
- Pi is behind firewall/NAT
- Need port forwarding or use ngrok

## Alternative: Using ngrok (For Testing Behind NAT)

If your Pi is behind a router without port forwarding:

1. **Install ngrok:**
   ```bash
   # Download ngrok
   wget https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz
   tar xvzf ngrok-v3-stable-linux-arm.tgz
   sudo mv ngrok /usr/local/bin/
   ```

2. **Start ngrok tunnel:**
   ```bash
   ngrok http 9000
   ```

3. **Use ngrok URL in GitHub webhook:**
   - Copy the HTTPS URL from ngrok (e.g., `https://abc123.ngrok.io`)
   - Use: `https://abc123.ngrok.io/webhook` as Payload URL

**Note**: ngrok free URLs change on restart. For production, use proper port forwarding.

## Summary

- ✅ **Script provides**: Secret, IP address, webhook URL
- ❌ **You must do**: Create webhook in GitHub web interface
- ⏱️ **Time needed**: 2-3 minutes
- 🔄 **One-time setup**: After this, auto-updates work automatically

The manual step is simple - just copy and paste the information the script provides into GitHub!

