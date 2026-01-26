# Quick Start with ngrok (No Router Config!)

## What is ngrok?

ngrok creates a secure tunnel from your Pi to the internet. **No router configuration needed!**

## Setup Steps

### 1. Run Setup Script

```bash
./setup-deployment-from-scratch.sh
```

This will automatically set up ngrok when you reach Step 12.

### 2. Or Set Up ngrok Manually

```bash
./setup-ngrok.sh
```

You'll need:
- Free ngrok account: https://dashboard.ngrok.com/signup
- Authtoken from: https://dashboard.ngrok.com/get-started/your-authtoken

### 3. Get Webhook URL

```bash
./get-ngrok-url.sh
```

This shows your public webhook URL and secret.

### 4. Add to GitHub

1. Go to: https://github.com/thienanlktl/Pideployment/settings/hooks
2. Click "Add webhook"
3. **Payload URL:** (from `./get-ngrok-url.sh`)
4. **Secret:** (from `.webhook_secret` file)
5. **Content type:** `application/json`
6. **Events:** Just the push event
7. Click "Add webhook"

## That's It!

No router configuration needed. ngrok handles everything.

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

ngrok free accounts get a new URL each time. To get a fixed URL:

1. Upgrade to ngrok paid plan, OR
2. Use cron fallback instead: `./setup-cron-fallback.sh`

## Troubleshooting

**ngrok not working?**
```bash
# Check if running
sudo systemctl status iot-gui-ngrok.service

# View logs
sudo journalctl -u iot-gui-ngrok.service -f

# View ngrok dashboard
# Open browser: http://localhost:4040
```

**Get current URL:**
```bash
./get-ngrok-url.sh
```

**Restart ngrok:**
```bash
sudo systemctl restart iot-gui-ngrok.service
```

