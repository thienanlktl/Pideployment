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
import threading
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
# Trim whitespace from secret to avoid issues
WEBHOOK_SECRET = os.environ.get('WEBHOOK_SECRET', 'change-me-to-a-strong-secret-key').strip()
WEBHOOK_PORT = int(os.environ.get('WEBHOOK_PORT', '9000'))
WEBHOOK_HOST = os.environ.get('WEBHOOK_HOST', '0.0.0.0')  # Listen on all interfaces

# Project directory (where this script is located)
SCRIPT_DIR = Path(__file__).parent.absolute()
UPDATE_SCRIPT = SCRIPT_DIR / "update-and-restart.sh"
LOG_FILE = SCRIPT_DIR / "webhook.log"
UPDATE_LOG_FILE = SCRIPT_DIR / "update.log"

# Target branch to monitor
TARGET_BRANCH = os.environ.get('GIT_BRANCH', 'main')

# In-memory log storage for API endpoint (last 100 entries)
log_entries = []
MAX_LOG_ENTRIES = 100

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
    # If secret is blank/empty, skip verification (GitHub allows blank secrets)
    if not WEBHOOK_SECRET or WEBHOOK_SECRET.strip() == '' or WEBHOOK_SECRET == 'change-me-to-a-strong-secret-key':
        if signature_header:
            logger.warning("Webhook secret is blank/empty, but signature header provided - skipping verification")
        else:
            logger.info("Webhook secret is blank/empty - signature verification skipped")
        return True  # Allow request when secret is blank
    
    # If secret is set but no signature provided, reject
    if not signature_header:
        logger.warning("No signature header provided but secret is configured")
        logger.warning("GitHub webhook signature verification requires X-Hub-Signature-256 header")
        return False
    
    # GitHub sends signature as: sha256=<hash>
    if not signature_header.startswith('sha256='):
        logger.warning(f"Invalid signature format. Expected 'sha256=...', got: {signature_header[:20]}...")
        return False
    
    # Extract hash from header
    received_hash = signature_header[7:]  # Remove 'sha256=' prefix
    
    # Calculate expected hash
    try:
        expected_hash = hmac.new(
            WEBHOOK_SECRET.encode('utf-8'),
            payload_body,
            hashlib.sha256
        ).hexdigest()
    except Exception as e:
        logger.error(f"Error calculating signature hash: {e}")
        return False
    
    # Use constant-time comparison to prevent timing attacks
    is_valid = hmac.compare_digest(received_hash, expected_hash)
    
    if not is_valid:
        logger.warning("Signature verification failed!")
        logger.warning(f"Received hash (first 10 chars): {received_hash[:10]}...")
        logger.warning(f"Expected hash (first 10 chars): {expected_hash[:10]}...")
        logger.warning("This usually means the webhook secret in GitHub doesn't match the secret in .webhook_secret file")
        logger.warning(f"Secret length: {len(WEBHOOK_SECRET)} characters")
    
    return is_valid


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


def add_log_entry(level, message, data=None):
    """
    Add a log entry to in-memory storage for API endpoint
    
    Args:
        level: Log level (info, warning, error, success)
        message: Log message
        data: Additional data dictionary
    """
    entry = {
        'timestamp': datetime.now().isoformat(),
        'level': level,
        'message': message,
        'data': data or {}
    }
    log_entries.append(entry)
    # Keep only last MAX_LOG_ENTRIES entries
    if len(log_entries) > MAX_LOG_ENTRIES:
        log_entries.pop(0)


def run_update_script():
    """
    Execute the update-and-restart.sh script
    This script will:
    1. Pull latest code from main branch
    2. Update Python dependencies
    3. Stop the running iot_pubsub_gui.py application
    4. Restart iot_pubsub_gui.py with the latest code
    
    Returns:
        tuple: (success: bool, output: str, error: str)
    """
    start_time = datetime.now()
    logger.info("=" * 60)
    logger.info("Starting UI update process via update-and-restart.sh")
    logger.info(f"Script: {UPDATE_SCRIPT}")
    logger.info("This will update and restart iot_pubsub_gui.py application")
    logger.info("=" * 60)
    
    add_log_entry('info', 'Starting UI update via update-and-restart script', {
        'script_path': str(UPDATE_SCRIPT),
        'ui_application': 'iot_pubsub_gui.py',
        'action': 'update_and_restart_ui',
        'timestamp': start_time.isoformat()
    })
    
    if not UPDATE_SCRIPT.exists():
        error_msg = f"Update script not found: {UPDATE_SCRIPT}"
        logger.error(error_msg)
        add_log_entry('error', error_msg, {'ui_application': 'iot_pubsub_gui.py'})
        return False, "", error_msg
    
    if not os.access(UPDATE_SCRIPT, os.X_OK):
        # Make script executable
        os.chmod(UPDATE_SCRIPT, 0o755)
        logger.info(f"Made update script executable: {UPDATE_SCRIPT}")
        add_log_entry('info', f"Made update script executable: {UPDATE_SCRIPT}")
    
    logger.info(f"Executing update script to update UI: {UPDATE_SCRIPT}")
    logger.info("This will pull latest code and restart iot_pubsub_gui.py")
    add_log_entry('info', f"Executing update script to update UI application: {UPDATE_SCRIPT}", {
        'ui_application': 'iot_pubsub_gui.py'
    })
    
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
        
        end_time = datetime.now()
        duration = (end_time - start_time).total_seconds()
        
        if result.returncode == 0:
            logger.info("=" * 60)
            logger.info("UI update script completed successfully")
            logger.info("iot_pubsub_gui.py has been updated and restarted")
            logger.info("=" * 60)
            add_log_entry('success', 'UI update script completed successfully', {
                'return_code': result.returncode,
                'duration_seconds': duration,
                'ui_application': 'iot_pubsub_gui.py',
                'action': 'update_and_restart_ui',
                'output_length': len(result.stdout),
                'output_preview': result.stdout[-500:] if result.stdout else ''
            })
            return True, result.stdout, result.stderr
        else:
            error_msg = f"UI update script failed with return code {result.returncode}"
            logger.error("=" * 60)
            logger.error(error_msg)
            logger.error(f"STDERR: {result.stderr}")
            logger.error("=" * 60)
            add_log_entry('error', error_msg, {
                'return_code': result.returncode,
                'duration_seconds': duration,
                'ui_application': 'iot_pubsub_gui.py',
                'action': 'update_and_restart_ui',
                'stderr': result.stderr[-1000:] if result.stderr else '',
                'stdout': result.stdout[-1000:] if result.stdout else ''
            })
            return False, result.stdout, result.stderr
            
    except subprocess.TimeoutExpired:
        error_msg = "Update script timed out after 10 minutes"
        logger.error(error_msg)
        add_log_entry('error', error_msg)
        return False, "", error_msg
    except Exception as e:
        error_msg = f"Error running update script: {e}"
        logger.error(error_msg)
        add_log_entry('error', error_msg, {'exception': str(e)})
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
    
    # Run update script in background thread to keep webhook listener responsive
    logger.info("Triggering update and restart in background...")
    add_log_entry('info', 'Webhook triggered update and restart (running in background)', {
        'event_type': event_type,
        'branch': TARGET_BRANCH,
        'commit_count': commit_count,
        'commit_messages': commit_messages
    })
    
    def run_update_in_background():
        """Run update script in background thread"""
        try:
            success, output, error = run_update_script()
            
            if success:
                logger.info("Update and restart completed successfully (background)")
                add_log_entry('success', 'Update and restart completed successfully via webhook (background)', {
                    'commits': commit_count
                })
            else:
                logger.error(f"Update and restart failed (background): {error}")
                add_log_entry('error', 'Update and restart failed via webhook (background)', {
                    'error': error[:500]
                })
        except Exception as e:
            logger.error(f"Error in background update thread: {e}")
            add_log_entry('error', f'Background update thread error: {str(e)}')
    
    # Start update in background thread
    update_thread = threading.Thread(target=run_update_in_background, daemon=True)
    update_thread.start()
    
    # Return immediately so webhook listener can continue handling requests
    logger.info("Update process started in background, webhook listener continues running")
    return jsonify({
        'status': 'accepted',
        'message': 'Update and restart triggered successfully (running in background)',
        'commits': commit_count,
        'timestamp': datetime.now().isoformat(),
        'note': 'The update is running in the background. Check logs for completion status.'
    }), 202  # 202 Accepted - request accepted for processing


@app.route('/health', methods=['GET'])
def health():
    """
    Health check endpoint with webhook secret status
    """
    secret_status = "configured" if WEBHOOK_SECRET and WEBHOOK_SECRET != 'change-me-to-a-strong-secret-key' else "not_configured"
    secret_length = len(WEBHOOK_SECRET) if WEBHOOK_SECRET else 0
    
    return jsonify({
        'status': 'healthy',
        'service': 'iot-gui-webhook',
        'timestamp': datetime.now().isoformat(),
        'update_script_exists': UPDATE_SCRIPT.exists(),
        'target_branch': TARGET_BRANCH,
        'webhook_secret_status': secret_status,
        'webhook_secret_length': secret_length,
        'note': 'If webhook secret is not_configured, ensure .webhook_secret file exists and matches GitHub webhook secret'
    }), 200


@app.route('/logs', methods=['GET'])
def logs():
    """
    API endpoint to retrieve update and restart logs
    Supports query parameters:
    - limit: Number of log entries to return (default: 50, max: 100)
    - level: Filter by log level (info, warning, error, success)
    - since: ISO timestamp to get logs since (e.g., 2024-01-01T00:00:00)
    """
    try:
        # Get query parameters
        limit = int(request.args.get('limit', 50))
        level_filter = request.args.get('level', None)
        since_str = request.args.get('since', None)
        
        # Limit max entries
        limit = min(limit, MAX_LOG_ENTRIES)
        
        # Filter logs
        filtered_logs = log_entries.copy()
        
        # Filter by level if specified
        if level_filter:
            filtered_logs = [log for log in filtered_logs if log['level'] == level_filter]
        
        # Filter by timestamp if specified
        if since_str:
            try:
                since_time = datetime.fromisoformat(since_str.replace('Z', '+00:00'))
                filtered_logs = [
                    log for log in filtered_logs 
                    if datetime.fromisoformat(log['timestamp']) >= since_time
                ]
            except ValueError:
                return jsonify({
                    'error': 'Invalid timestamp format. Use ISO format (e.g., 2024-01-01T00:00:00)'
                }), 400
        
        # Get last N entries
        filtered_logs = filtered_logs[-limit:]
        
        # Also try to read from update.log file if it exists
        update_log_content = None
        if UPDATE_LOG_FILE.exists():
            try:
                with open(UPDATE_LOG_FILE, 'r') as f:
                    update_log_content = f.read()
            except Exception as e:
                logger.warning(f"Could not read update.log: {e}")
        
        return jsonify({
            'status': 'success',
            'log_entries': filtered_logs,
            'total_entries': len(filtered_logs),
            'total_stored': len(log_entries),
            'update_log_file': str(UPDATE_LOG_FILE),
            'update_log_exists': UPDATE_LOG_FILE.exists(),
            'update_log_preview': update_log_content[-2000:] if update_log_content else None,
            'timestamp': datetime.now().isoformat()
        }), 200
        
    except Exception as e:
        logger.error(f"Error retrieving logs: {e}")
        return jsonify({
            'status': 'error',
            'error': str(e)
        }), 500


@app.route('/trigger', methods=['GET', 'POST'])
def trigger():
    """
    Manual trigger endpoint to run update-and-restart.sh
    Can be called via GET or POST request
    Runs update in background to keep listener responsive
    """
    logger.info("Manual trigger endpoint called - running update script in background")
    add_log_entry('info', 'Manual trigger endpoint called (running in background)', {
        'method': request.method,
        'remote_addr': request.remote_addr
    })
    
    def run_update_in_background():
        """Run update script in background thread"""
        try:
            success, output, error = run_update_script()
            
            if success:
                logger.info("Update and restart completed successfully (manual trigger, background)")
                add_log_entry('success', 'Update and restart completed successfully (manual trigger, background)', {
                    'output_length': len(output) if output else 0
                })
            else:
                logger.error(f"Update and restart failed (manual trigger, background): {error}")
                add_log_entry('error', 'Update and restart failed (manual trigger, background)', {
                    'error': error[-1000:] if error else 'Unknown error'
                })
        except Exception as e:
            logger.error(f"Error in background update thread (manual trigger): {e}")
            add_log_entry('error', f'Background update thread error (manual trigger): {str(e)}')
    
    # Start update in background thread
    update_thread = threading.Thread(target=run_update_in_background, daemon=True)
    update_thread.start()
    
    # Return immediately so webhook listener can continue handling requests
    logger.info("Update process started in background (manual trigger), webhook listener continues running")
    return jsonify({
        'status': 'accepted',
        'message': 'Update and restart triggered successfully (running in background)',
        'timestamp': datetime.now().isoformat(),
        'note': 'The update is running in the background. Check logs for completion status.'
    }), 202  # 202 Accepted - request accepted for processing


@app.route('/', methods=['GET', 'POST'])
def index():
    """
    Root endpoint - handles both GET and POST requests
    - GET: triggers update-and-restart.sh when accessed
    - POST: handles GitHub webhook events (when webhook URL is set to root)
    """
    # Handle POST requests as webhooks (when GitHub sends to root URL)
    if request.method == 'POST':
        logger.info("Root endpoint received POST request - treating as webhook")
        # Get raw payload for signature verification
        payload_body = request.get_data()
        
        # Get signature from header
        signature = request.headers.get('X-Hub-Signature-256', '')
        
        # Verify signature (will skip if secret is blank)
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
        logger.info(f"Received webhook event at root endpoint: {event_type}")
        
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
            commit_count = 0
            commit_messages = []
        
        # Run update script in background thread to keep webhook listener responsive
        logger.info("Triggering update and restart in background...")
        add_log_entry('info', 'Webhook triggered update and restart (root endpoint, running in background)', {
            'event_type': event_type,
            'branch': TARGET_BRANCH,
            'commit_count': commit_count,
            'commit_messages': commit_messages
        })
        
        def run_update_in_background():
            """Run update script in background thread"""
            try:
                success, output, error = run_update_script()
                
                if success:
                    logger.info("Update and restart completed successfully (root endpoint webhook, background)")
                    add_log_entry('success', 'Update and restart completed successfully via webhook at root (background)', {
                        'commits': commit_count
                    })
                else:
                    logger.error(f"Update and restart failed (root endpoint webhook, background): {error}")
                    add_log_entry('error', 'Update and restart failed via webhook at root (background)', {
                        'error': error[:500]
                    })
            except Exception as e:
                logger.error(f"Error in background update thread (root endpoint webhook): {e}")
                add_log_entry('error', f'Background update thread error (root endpoint webhook): {str(e)}')
        
        # Start update in background thread
        update_thread = threading.Thread(target=run_update_in_background, daemon=True)
        update_thread.start()
        
        # Return immediately so webhook listener can continue handling requests
        logger.info("Update process started in background (webhook at root), webhook listener continues running")
        return jsonify({
            'status': 'accepted',
            'message': 'Update and restart triggered successfully (running in background)',
            'commits': commit_count,
            'timestamp': datetime.now().isoformat(),
            'note': 'The update is running in the background. Check logs for completion status.'
        }), 202  # 202 Accepted - request accepted for processing
    
    # Handle GET requests (original behavior)
    logger.info("Root endpoint accessed - triggering UI update via update-and-restart.sh")
    logger.info("This will update and restart iot_pubsub_gui.py application")
    
    add_log_entry('info', 'Root endpoint accessed - triggering UI update', {
        'remote_addr': request.remote_addr,
        'action': 'update_and_restart_ui',
        'ui_application': 'iot_pubsub_gui.py'
    })
    
    # Run update script in background thread to keep webhook listener responsive
    logger.info("Executing update-and-restart.sh to update UI application (running in background)...")
    
    def run_update_in_background():
        """Run update script in background thread"""
        try:
            success, output, error = run_update_script()
            
            if success:
                logger.info("UI update and restart completed successfully (root endpoint trigger, background)")
                logger.info("iot_pubsub_gui.py has been updated and restarted with latest code")
                add_log_entry('success', 'UI update and restart completed successfully (root endpoint trigger, background)', {
                    'ui_application': 'iot_pubsub_gui.py',
                    'action': 'update_and_restart_ui'
                })
            else:
                logger.error(f"UI update and restart failed (root endpoint trigger, background): {error}")
                add_log_entry('error', 'UI update and restart failed (root endpoint trigger, background)', {
                    'ui_application': 'iot_pubsub_gui.py',
                    'error': error[-500:] if error else 'Unknown error'
                })
        except Exception as e:
            logger.error(f"Error in background update thread (root endpoint): {e}")
            add_log_entry('error', f'Background update thread error (root endpoint): {str(e)}')
    
    # Start update in background thread
    update_thread = threading.Thread(target=run_update_in_background, daemon=True)
    update_thread.start()
    
    # Return immediately so webhook listener can continue handling requests
    logger.info("Update process started in background (root endpoint), webhook listener continues running")
    return jsonify({
        'status': 'accepted',
        'message': 'UI application (iot_pubsub_gui.py) update and restart triggered successfully (running in background)',
        'ui_application': 'iot_pubsub_gui.py',
        'action': 'update_and_restart',
        'service': 'GitHub Webhook Listener for AWS IoT Pub/Sub GUI',
        'endpoints': {
            'webhook': '/webhook (POST)',
            'health': '/health (GET)',
            'trigger': '/trigger (GET/POST) - Manually trigger update-and-restart.sh',
            'logs': '/logs (GET) - View update and restart logs'
        },
        'target_branch': TARGET_BRANCH,
        'timestamp': datetime.now().isoformat(),
        'note': 'The update is running in the background. Check logs for completion status.'
    }), 202  # 202 Accepted - request accepted for processing


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
    
    # Add startup log entry
    add_log_entry('info', 'Webhook listener started', {
        'host': WEBHOOK_HOST,
        'port': WEBHOOK_PORT,
        'target_branch': TARGET_BRANCH,
        'update_script': str(UPDATE_SCRIPT)
    })
    
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

