# Quick GitHub Webhook Setup

## Option 1: Automatic (Recommended) ✅

**No manual steps needed!** Just run:

```bash
./create-github-webhook.sh
```

**What you need:**
- GitHub Personal Access Token
  - Create at: https://github.com/settings/tokens
  - Required scope: `repo` (for private) or `public_repo` (for public)
- ngrok URL (automatically detected)
- Webhook secret (automatically loaded from `.webhook_secret`)

The script will:
1. Ask for your GitHub token (or use from environment variable)
2. Get ngrok URL automatically
3. Get webhook secret automatically
4. Create/update the webhook via GitHub API
5. Verify it's working

**One-time token setup:**
```bash
# Save token for future use
echo "your_github_token" > .github_token
chmod 600 .github_token

# Or use environment variable
export GITHUB_TOKEN="your_github_token"
./create-github-webhook.sh
```

## Option 2: Manual Setup

If you prefer to create it manually:

1. **Get webhook URL:**
   ```bash
   ./get-ngrok-url.sh
   ```

2. **Go to GitHub:**
   - https://github.com/thienanlktl/Pideployment/settings/hooks

3. **Click "Add webhook"**

4. **Fill in:**
   - **Payload URL:** (from step 1)
   - **Content type:** `application/json`
   - **Secret:** (from `.webhook_secret` file)
   - **Events:** Just the push event

5. **Click "Add webhook"**

## Verify Webhook

After creating (automatic or manual):

1. **Check in GitHub:**
   - Go to: https://github.com/thienanlktl/Pideployment/settings/hooks
   - You should see a green checkmark ✓

2. **Test it:**
   - Make a small change to your repo
   - Push to main branch
   - Check webhook logs: `sudo journalctl -u iot-gui-webhook.service -f`

## Troubleshooting

**Webhook not receiving events?**
- Check ngrok is running: `sudo systemctl status iot-gui-ngrok.service`
- Check webhook service: `sudo systemctl status iot-gui-webhook.service`
- Verify URL in GitHub matches ngrok URL: `./get-ngrok-url.sh`
- Check GitHub webhook delivery logs in GitHub settings

**Token issues?**
- Verify token has `repo` scope
- Check token hasn't expired
- Regenerate if needed: https://github.com/settings/tokens

**ngrok URL changed?**
- Free ngrok accounts get new URL on restart
- Run `./create-github-webhook.sh` again to update
- Or use cron fallback: `./setup-cron-fallback.sh`

