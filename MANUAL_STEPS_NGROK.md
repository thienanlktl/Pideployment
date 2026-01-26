# Manual Steps with ngrok (No Router Config!)

## Summary

After running `setup-deployment-from-scratch.sh`, you only need to:

1. **Set up ngrok** (one-time, on Pi only)
2. **Add webhook to GitHub** (one-time)

**No router configuration needed!**

## Step 1: Set Up ngrok

### Option A: During Setup Script

The `setup-deployment-from-scratch.sh` script will prompt you to set up ngrok at Step 12.

### Option B: Manual Setup

```bash
./setup-ngrok.sh
```

**What you need:**
1. Free ngrok account: https://dashboard.ngrok.com/signup
2. Authtoken: https://dashboard.ngrok.com/get-started/your-authtoken

**The script will:**
- Install ngrok
- Configure authtoken
- Create tunnel
- Set up systemd service
- Show your public webhook URL

## Step 2: Get Webhook URL

```bash
./get-ngrok-url.sh
```

This shows:
- Your public webhook URL
- Your webhook secret
- GitHub webhook configuration details

## Step 3: Add Webhook to GitHub

1. Go to: https://github.com/thienanlktl/Pideployment/settings/hooks
2. Click "Add webhook"
3. **Payload URL:** (from `./get-ngrok-url.sh` output)
4. **Secret:** (from `.webhook_secret` file or `./get-ngrok-url.sh` output)
5. **Content type:** `application/json`
6. **Events:** Just the push event
7. Click "Add webhook"

## That's It!

No router configuration. Everything runs on your Pi.

## Services

Two services run automatically:

- **iot-gui-webhook.service** - Listens for GitHub webhooks
- **iot-gui-ngrok.service** - Creates public tunnel

Check status:
```bash
sudo systemctl status iot-gui-webhook.service
sudo systemctl status iot-gui-ngrok.service
```

## If ngrok URL Changes

**Free ngrok accounts:** URL changes each time ngrok restarts.

**Solutions:**
1. **Upgrade to ngrok paid plan** - Get fixed domain
2. **Use cron fallback** - `./setup-cron-fallback.sh` (checks GitHub every 5-10 min)
3. **Update GitHub webhook** - Run `./get-ngrok-url.sh` and update URL in GitHub

## Troubleshooting

**ngrok not running?**
```bash
sudo systemctl start iot-gui-ngrok.service
sudo systemctl status iot-gui-ngrok.service
```

**View ngrok logs:**
```bash
sudo journalctl -u iot-gui-ngrok.service -f
```

**View ngrok dashboard:**
Open browser on Pi: http://localhost:4040

**Get current URL:**
```bash
./get-ngrok-url.sh
```

## Quick Reference

```bash
# Get webhook URL and secret
./get-ngrok-url.sh

# Check services
sudo systemctl status iot-gui-webhook.service
sudo systemctl status iot-gui-ngrok.service

# Restart services
sudo systemctl restart iot-gui-webhook.service
sudo systemctl restart iot-gui-ngrok.service

# View logs
sudo journalctl -u iot-gui-webhook.service -f
sudo journalctl -u iot-gui-ngrok.service -f
```

