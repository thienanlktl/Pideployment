# Quick Deployment Reference

## 🚀 Quick Start: Setup Everything from Scratch

**One command to set up everything:**
```bash
chmod +x setup-deployment-from-scratch.sh && ./setup-deployment-from-scratch.sh
```

This will handle all setup automatically. You just need to add the SSH key and webhook to GitHub afterward.

---

## One-Line Commands

### Complete Setup from Scratch (Recommended)
```bash
./setup-deployment-from-scratch.sh
```

### Generate SSH Key and Display Public Key
```bash
./setup-ssh-key.sh
```

### Test Update Script Manually
```bash
./update-and-restart.sh
```

### Start Webhook Listener (Manual)
```bash
source venv/bin/activate
export WEBHOOK_SECRET="your-secret-here"
python webhook_listener.py
```

### Set Up Systemd Service
```bash
sudo cp iot-gui-webhook.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable iot-gui-webhook.service
sudo systemctl start iot-gui-webhook.service
```

### Set Up Cron Fallback
```bash
./setup-cron-fallback.sh
```

## GitHub Setup Checklist

- [ ] Generate SSH key: `./setup-ssh-key.sh`
- [ ] Copy public key from output
- [ ] Add deploy key at: `https://github.com/thienanlktl/Pideployment/settings/keys`
- [ ] Update git remote: 
  - SSH: `git remote set-url origin git@github.com:thienanlktl/Pideployment.git`
  - HTTPS: `git remote set-url origin https://github.com/thienanlktl/Pideployment.git`
- [ ] Test SSH: `ssh -T git@github.com` (if using SSH)
- [ ] Generate webhook secret: `python3 -c "import secrets; print(secrets.token_urlsafe(32))"`
- [ ] Add webhook at: `https://github.com/thienanlktl/Pideployment/settings/hooks`
  - URL: `http://YOUR_PI_IP:9000/webhook`
  - Secret: (paste generated secret)
  - Events: Just the push event

## Service Management

```bash
# Status
sudo systemctl status iot-gui-webhook.service

# Start
sudo systemctl start iot-gui-webhook.service

# Stop
sudo systemctl stop iot-gui-webhook.service

# Restart
sudo systemctl restart iot-gui-webhook.service

# View logs
sudo journalctl -u iot-gui-webhook.service -f
```

## Log Files

- Webhook logs: `webhook.log`
- Update logs: `update.log`
- Cron logs: `cron.log` (if using cron)
- Systemd logs: `sudo journalctl -u iot-gui-webhook.service`

## Testing

### Test Webhook Health Endpoint
```bash
curl http://localhost:9000/health
```

### Test Webhook Manually
```bash
curl -X POST http://localhost:9000/webhook \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: push" \
  -H "X-Hub-Signature-256: sha256=$(echo -n '{"ref":"refs/heads/main"}' | openssl dgst -sha256 -hmac 'your-secret' | cut -d' ' -f2)" \
  -d '{"ref":"refs/heads/main"}'
```

### Check Application Status
```bash
# Check if running
ps aux | grep iot_pubsub_gui.py

# Check PID file
cat app.pid
```

## Troubleshooting Quick Fixes

### Webhook Not Working
```bash
# Check if running
sudo systemctl status iot-gui-webhook.service

# Check firewall
sudo ufw allow 9000/tcp

# Check logs
sudo journalctl -u iot-gui-webhook.service -n 50
```

### Git Pull Fails
```bash
# Test SSH
ssh -T git@github.com

# Check remote
git remote -v

# Manual pull
git pull origin main
```

### Application Not Restarting
```bash
# Check logs
tail -f update.log

# Manual restart
./update-and-restart.sh
```

## File Locations

- Project directory: `~/PublishDemo` (or your path)
- SSH key: `~/.ssh/id_ed25519_iot_gui`
- Service file: `/etc/systemd/system/iot-gui-webhook.service`
- Logs: `~/PublishDemo/update.log`, `webhook.log`

