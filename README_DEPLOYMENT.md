# Automated Deployment - Quick Start

## One-Command Setup (Recommended)

Run this single command to set up everything from scratch:

```bash
chmod +x setup-deployment-from-scratch.sh && ./setup-deployment-from-scratch.sh
```

That's it! The script will:
- Install all dependencies
- Generate SSH keys
- Configure git
- Set up webhook listener
- Install systemd service

## What You Need to Do

After running the script, you'll need to:

1. **Add SSH key to GitHub** (script will show you the key)
   - Go to: `https://github.com/thienanlktl/Pideployment/settings/keys`
   - Click "Add deploy key"
   - Paste the public key

2. **Add webhook to GitHub** (script will show you the URL and secret)
   - Go to: `https://github.com/thienanlktl/Pideployment/settings/hooks`
   - Click "Add webhook"
   - URL: `http://YOUR_PI_IP:9000/webhook`
   - Secret: (paste from script output)
   - Events: Just the push event

## That's It!

Once configured, every time you push to the `main` branch:
1. GitHub sends a webhook to your Pi
2. Pi pulls the latest code
3. Updates dependencies if needed
4. Restarts the application automatically

## Testing

```bash
# Test webhook health
curl http://localhost:9000/health

# Test manual update
./update-and-restart.sh

# Check service status
sudo systemctl status iot-gui-webhook.service

# View logs
sudo journalctl -u iot-gui-webhook.service -f
```

## Troubleshooting

See `DEPLOYMENT_SETUP.md` for detailed troubleshooting guide.

## Files

- `setup-deployment-from-scratch.sh` - Master setup script (use this!)
- `update-and-restart.sh` - Update and restart script
- `webhook_listener.py` - Webhook listener service
- `DEPLOYMENT_SETUP.md` - Detailed setup guide
- `QUICK_DEPLOYMENT_REFERENCE.md` - Command reference

