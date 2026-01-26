#!/usr/bin/env python3
"""
GitHub Webhook Listener for AWS IoT Pub/Sub GUI
Listens for GitHub push events and triggers application update/restart

Usage:
    python webhook_listener.py

Or run as systemd service (see iot-gui-webhook.service)
"""

import os
import sys
import hmac
import hashlib
import subprocess
import json
import logging
from pathlib import Path
from datetime import datetime

try:
    from flask import Flask, request, jsonify, abort
except ImportError:
    print("ERROR: Flask is not installed. Install it with:")
    print("  pip install flask")
    sys.exit(1)

# ============================================================================
# Configuration
# ============================================================================

# Webhook secret (set via environment variable or default)
WEBHOOK_SECRET = os.environ.get('WEBHOOK_SECRET', 'change-me-to-a-strong-secret-key')
WEBHOOK_PORT = int(os.environ.get('WEBHOOK_PORT', '9000'))
WEBHOOK_HOST = os.environ.get('WEBHOOK_HOST', '0.0.0.0')  # Listen on all interfaces

# Project directory (where this script is located)
SCRIPT_DIR = Path(__file__).parent.absolute()
UPDATE_SCRIPT = SCRIPT_DIR / "update-and-restart.sh"
LOG_FILE = SCRIPT_DIR / "webhook.log"

# Target branch to monitor
TARGET_BRANCH = os.environ.get('GIT_BRANCH', 'main')

# ============================================================================
# Logging Setup
# ============================================================================

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout)
    ]
)

logger = logging.getLogger(__name__)

# ============================================================================
# Flask Application
# ============================================================================

app = Flask(__name__)

# ============================================================================
# Helper Functions
# ============================================================================

def verify_webhook_signature(payload_body, signature_header):
    """
    Verify GitHub webhook signature using HMAC SHA256
    
    Args:
        payload_body: Raw request body (bytes)
        signature_header: X-Hub-Signature-256 header value
        
    Returns:
        bool: True if signature is valid, False otherwise
    """
    if not signature_header:
        logger.warning("No signature header provided")
        return False
    
    # GitHub sends signature as: sha256=<hash>
    if not signature_header.startswith('sha256='):
        logger.warning("Invalid signature format")
        return False
    
    # Extract hash from header
    received_hash = signature_header[7:]  # Remove 'sha256=' prefix
    
    # Calculate expected hash
    expected_hash = hmac.new(
        WEBHOOK_SECRET.encode('utf-8'),
        payload_body,
        hashlib.sha256
    ).hexdigest()
    
    # Use constant-time comparison to prevent timing attacks
    return hmac.compare_digest(received_hash, expected_hash)


def is_push_to_main(payload):
    """
    Check if the webhook payload is a push event to the main branch
    
    Args:
        payload: Parsed JSON payload from GitHub
        
    Returns:
        bool: True if push to main branch, False otherwise
    """
    try:
        # Check event type
        if payload.get('ref') is None:
            return False
        
        # Extract branch name from ref (e.g., 'refs/heads/main')
        ref = payload.get('ref', '')
        branch = ref.replace('refs/heads/', '')
        
        # Check if it's the target branch
        if branch == TARGET_BRANCH:
            logger.info(f"Push detected to target branch: {branch}")
            return True
        
        logger.info(f"Push detected to non-target branch: {branch}")
        return False
        
    except Exception as e:
        logger.error(f"Error checking branch: {e}")
        return False


def run_update_script():
    """
    Execute the update-and-restart.sh script
    
    Returns:
        tuple: (success: bool, output: str, error: str)
    """
    if not UPDATE_SCRIPT.exists():
        error_msg = f"Update script not found: {UPDATE_SCRIPT}"
        logger.error(error_msg)
        return False, "", error_msg
    
    if not os.access(UPDATE_SCRIPT, os.X_OK):
        # Make script executable
        os.chmod(UPDATE_SCRIPT, 0o755)
        logger.info(f"Made update script executable: {UPDATE_SCRIPT}")
    
    logger.info(f"Executing update script: {UPDATE_SCRIPT}")
    
    try:
        # Prepare environment with DISPLAY and PATH
        env = dict(os.environ)
        env['DISPLAY'] = os.environ.get('DISPLAY', ':0')
        # Ensure venv Python is in PATH
        venv_bin = SCRIPT_DIR / "venv" / "bin"
        if venv_bin.exists():
            env['PATH'] = str(venv_bin) + os.pathsep + env.get('PATH', '')
        
        # Run the update script
        result = subprocess.run(
            ['/bin/bash', str(UPDATE_SCRIPT)],
            cwd=SCRIPT_DIR,
            capture_output=True,
            text=True,
            timeout=600,  # 10 minute timeout
            env=env
        )
        
        if result.returncode == 0:
            logger.info("Update script completed successfully")
            return True, result.stdout, result.stderr
        else:
            error_msg = f"Update script failed with return code {result.returncode}"
            logger.error(error_msg)
            logger.error(f"STDERR: {result.stderr}")
            return False, result.stdout, result.stderr
            
    except subprocess.TimeoutExpired:
        error_msg = "Update script timed out after 10 minutes"
        logger.error(error_msg)
        return False, "", error_msg
    except Exception as e:
        error_msg = f"Error running update script: {e}"
        logger.error(error_msg)
        return False, "", error_msg


# ============================================================================
# Webhook Endpoints
# ============================================================================

@app.route('/webhook', methods=['POST'])
def webhook():
    """
    Main webhook endpoint for GitHub push events
    """
    # Get raw payload for signature verification
    payload_body = request.get_data()
    
    # Get signature from header
    signature = request.headers.get('X-Hub-Signature-256', '')
    
    # Verify signature
    if not verify_webhook_signature(payload_body, signature):
        logger.warning("Invalid webhook signature - rejecting request")
        abort(401, description="Invalid signature")
    
    # Parse JSON payload
    try:
        payload = json.loads(payload_body.decode('utf-8'))
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON payload: {e}")
        abort(400, description="Invalid JSON")
    
    # Log webhook event
    event_type = request.headers.get('X-GitHub-Event', 'unknown')
    logger.info(f"Received webhook event: {event_type}")
    
    # Only process push events
    if event_type != 'push':
        logger.info(f"Ignoring non-push event: {event_type}")
        return jsonify({
            'status': 'ignored',
            'message': f'Event type "{event_type}" is not a push event'
        }), 200
    
    # Check if push is to main branch
    if not is_push_to_main(payload):
        logger.info("Push event is not to target branch, ignoring")
        return jsonify({
            'status': 'ignored',
            'message': f'Push is not to {TARGET_BRANCH} branch'
        }), 200
    
    # Extract commit information
    try:
        commits = payload.get('commits', [])
        commit_count = len(commits)
        commit_messages = [c.get('message', '')[:50] for c in commits[:3]]
        
        logger.info(f"Processing push to {TARGET_BRANCH} with {commit_count} commit(s)")
        logger.info(f"Commit messages: {', '.join(commit_messages)}")
    except Exception as e:
        logger.warning(f"Could not extract commit info: {e}")
    
    # Run update script
    logger.info("Triggering update and restart...")
    success, output, error = run_update_script()
    
    if success:
        logger.info("Update and restart completed successfully")
        return jsonify({
            'status': 'success',
            'message': 'Update and restart triggered successfully',
            'commits': commit_count
        }), 200
    else:
        logger.error(f"Update and restart failed: {error}")
        return jsonify({
            'status': 'error',
            'message': 'Update and restart failed',
            'error': error[:500]  # Limit error message length
        }), 500


@app.route('/health', methods=['GET'])
def health():
    """
    Health check endpoint
    """
    return jsonify({
        'status': 'healthy',
        'service': 'iot-gui-webhook',
        'timestamp': datetime.now().isoformat(),
        'update_script_exists': UPDATE_SCRIPT.exists(),
        'target_branch': TARGET_BRANCH
    }), 200


@app.route('/trigger', methods=['GET', 'POST'])
def trigger():
    """
    Manual trigger endpoint to run update-and-restart.sh
    Can be called via GET or POST request
    """
    logger.info("Manual trigger endpoint called - running update script")
    
    # Run update script
    success, output, error = run_update_script()
    
    if success:
        logger.info("Update and restart completed successfully (manual trigger)")
        return jsonify({
            'status': 'success',
            'message': 'Update and restart triggered successfully',
            'output': output[-1000:] if output else ''  # Last 1000 chars of output
        }), 200
    else:
        logger.error(f"Update and restart failed (manual trigger): {error}")
        return jsonify({
            'status': 'error',
            'message': 'Update and restart failed',
            'error': error[-1000:] if error else 'Unknown error'  # Last 1000 chars of error
        }), 500


@app.route('/', methods=['GET'])
def index():
    """
    Root endpoint - triggers update-and-restart.sh when accessed
    """
    logger.info("Root endpoint accessed - triggering update script")
    
    # Run update script
    success, output, error = run_update_script()
    
    if success:
        logger.info("Update and restart completed successfully (root endpoint trigger)")
        return jsonify({
            'status': 'success',
            'message': 'Update and restart triggered successfully',
            'service': 'GitHub Webhook Listener for AWS IoT Pub/Sub GUI',
            'endpoints': {
                'webhook': '/webhook (POST)',
                'health': '/health (GET)',
                'trigger': '/trigger (GET/POST) - Manually trigger update-and-restart.sh'
            },
            'target_branch': TARGET_BRANCH,
            'output': output[-500:] if output else ''  # Last 500 chars of output
        }), 200
    else:
        logger.error(f"Update and restart failed (root endpoint trigger): {error}")
        return jsonify({
            'status': 'error',
            'message': 'Update and restart failed',
            'service': 'GitHub Webhook Listener for AWS IoT Pub/Sub GUI',
            'error': error[-500:] if error else 'Unknown error'  # Last 500 chars of error
        }), 500


# ============================================================================
# Main Entry Point
# ============================================================================

def main():
    """
    Main entry point for the webhook listener
    """
    # Check if update script exists
    if not UPDATE_SCRIPT.exists():
        logger.error(f"Update script not found: {UPDATE_SCRIPT}")
        logger.error("Please ensure update-and-restart.sh exists in the project directory")
        sys.exit(1)
    
    # Warn if using default secret
    if WEBHOOK_SECRET == 'change-me-to-a-strong-secret-key':
        logger.warning("=" * 60)
        logger.warning("WARNING: Using default webhook secret!")
        logger.warning("Set WEBHOOK_SECRET environment variable for security.")
        logger.warning("=" * 60)
    
    # Log startup information
    logger.info("=" * 60)
    logger.info("GitHub Webhook Listener Starting")
    logger.info("=" * 60)
    logger.info(f"Listening on: {WEBHOOK_HOST}:{WEBHOOK_PORT}")
    logger.info(f"Target branch: {TARGET_BRANCH}")
    logger.info(f"Update script: {UPDATE_SCRIPT}")
    logger.info(f"Log file: {LOG_FILE}")
    logger.info("=" * 60)
    
    # Start Flask server
    try:
        app.run(
            host=WEBHOOK_HOST,
            port=WEBHOOK_PORT,
            debug=False,  # Disable debug mode for production
            threaded=True
        )
    except KeyboardInterrupt:
        logger.info("Webhook listener stopped by user")
    except Exception as e:
        logger.error(f"Error starting webhook listener: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()

