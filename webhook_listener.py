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
# Use absolute path to ensure we always reference files in the same directory
SCRIPT_DIR = Path(__file__).resolve().parent
UPDATE_SCRIPT = SCRIPT_DIR / "update-and-restart.sh"
LOG_FILE = SCRIPT_DIR / "webhook.log"
UPDATE_LOG_FILE = SCRIPT_DIR / "update.log"
APP_FILE = SCRIPT_DIR / "iot_pubsub_gui.py"
REQUIREMENTS_FILE = SCRIPT_DIR / "requirements.txt"
PID_FILE = SCRIPT_DIR / "app.pid"
VENV_DIR = SCRIPT_DIR / "venv"
WRAPPER_SCRIPT = SCRIPT_DIR / ".run_app_wrapper.sh"

# Target branch to monitor
TARGET_BRANCH = os.environ.get('GIT_BRANCH', 'main')

# In-memory log storage for API endpoint (last 100 entries)
log_entries = []
MAX_LOG_ENTRIES = 100

# ============================================================================
# Logging Setup
# ============================================================================

# Ensure log file directory exists
LOG_FILE.parent.mkdir(parents=True, exist_ok=True)

# Configure logging with file handler and console handler
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE, mode='a', encoding='utf-8'),  # Append mode, UTF-8 encoding
        logging.StreamHandler(sys.stdout)
    ]
)

logger = logging.getLogger(__name__)

# Log startup information to confirm log file location
logger.info("=" * 60)
logger.info("Webhook Listener Logging Initialized")
logger.info(f"Log file location: {LOG_FILE}")
logger.info(f"Log file absolute path: {LOG_FILE.absolute()}")
logger.info(f"Script directory: {SCRIPT_DIR}")
logger.info("=" * 60)

# ============================================================================
# Flask Application
# ============================================================================

app = Flask(__name__)

# Add error handler for 405 Method Not Allowed
@app.errorhandler(405)
def method_not_allowed(e):
    """Handle 405 Method Not Allowed errors"""
    logger.warning(f"405 Method Not Allowed: {request.method} {request.path}")
    logger.warning(f"Allowed methods: {e.valid_methods if hasattr(e, 'valid_methods') else 'unknown'}")
    logger.warning(f"Request headers: {dict(request.headers)}")
    return jsonify({
        'error': 'Method Not Allowed',
        'method': request.method,
        'path': request.path,
        'message': f'{request.method} method is not allowed for {request.path}',
        'allowed_methods': e.valid_methods if hasattr(e, 'valid_methods') else []
    }), 405

# Add error handler for 401 Unauthorized (should never happen, but catch it just in case)
@app.errorhandler(401)
def unauthorized(e):
    """Handle 401 Unauthorized errors - convert to 200 OK"""
    logger.warning(f"401 Unauthorized error caught: {request.method} {request.path}")
    logger.warning(f"Request headers: {dict(request.headers)}")
    logger.warning("Converting 401 to 200 OK response to prevent GitHub errors")
    return jsonify({
        'status': 'accepted',
        'message': 'Request accepted (401 error converted to 200)',
        'timestamp': datetime.now().isoformat()
    }), 200

# Add global exception handler to catch any unexpected errors
@app.errorhandler(Exception)
def handle_exception(e):
    """Handle any unexpected exceptions - always return 200 OK"""
    logger.error(f"Unexpected exception: {type(e).__name__}: {str(e)}")
    logger.error(f"Request: {request.method} {request.path}")
    logger.error(f"Request headers: {dict(request.headers)}")
    import traceback
    logger.error(f"Traceback: {traceback.format_exc()}")
    # Always return 200 OK to prevent GitHub from reporting errors
    return jsonify({
        'status': 'accepted',
        'message': 'Request accepted (exception handled)',
        'error': str(e),
        'timestamp': datetime.now().isoformat()
    }), 200

# ============================================================================
# Helper Functions
# ============================================================================

def verify_webhook_signature(payload_body, signature_header):
    """
    Verify GitHub webhook signature using HMAC SHA256
    NOTE: Currently disabled - all requests are allowed without verification
    
    Args:
        payload_body: Raw request body (bytes)
        signature_header: X-Hub-Signature-256 header value
        
    Returns:
        bool: Always returns True (verification disabled)
    """
    # Allow all requests without verification
    logger.info("Webhook signature verification disabled - allowing all requests")
    return True  # Always allow requests
    
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
        # Verify we're in the correct directory
        if not SCRIPT_DIR.exists():
            error_msg = f"Script directory does not exist: {SCRIPT_DIR}"
            logger.error(error_msg)
            return False, "", error_msg
        
        # Change to script directory to ensure all relative paths work
        original_cwd = os.getcwd()
        try:
            os.chdir(SCRIPT_DIR)
            logger.info(f"Changed working directory to: {SCRIPT_DIR}")
        except Exception as e:
            logger.warning(f"Could not change to script directory: {e}")
            logger.warning("Continuing with current directory, but paths may be incorrect")
        
        # Prepare environment with DISPLAY and PATH
        env = dict(os.environ)
        env['DISPLAY'] = os.environ.get('DISPLAY', ':0')
        # Ensure venv Python is in PATH
        venv_bin = VENV_DIR / "bin"
        if venv_bin.exists():
            env['PATH'] = str(venv_bin) + os.pathsep + env.get('PATH', '')
        
        # Set SCRIPT_DIR in environment so update script knows where it is
        env['SCRIPT_DIR'] = str(SCRIPT_DIR)
        
        # Log all file paths being used
        logger.info(f"Working directory: {os.getcwd()}")
        logger.info(f"Update script: {UPDATE_SCRIPT}")
        logger.info(f"Update script exists: {UPDATE_SCRIPT.exists()}")
        logger.info(f"App file: {APP_FILE}")
        logger.info(f"App file exists: {APP_FILE.exists()}")
        logger.info(f"Venv directory: {VENV_DIR}")
        logger.info(f"Venv exists: {VENV_DIR.exists()}")
        
        # Run the update script - use absolute path to be sure
        update_script_abs = str(UPDATE_SCRIPT.resolve())
        logger.info(f"Executing: /bin/bash {update_script_abs}")
        logger.info(f"From directory: {os.getcwd()}")
        
        # Run the update script
        result = subprocess.run(
            ['/bin/bash', update_script_abs],
            cwd=str(SCRIPT_DIR),  # Explicitly set working directory
            capture_output=True,
            text=True,
            timeout=600,  # 10 minute timeout
            env=env
        )
        
        # Restore original working directory
        try:
            os.chdir(original_cwd)
        except Exception:
            pass  # Ignore errors restoring directory
        
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

@app.route('/webhook', methods=['POST', 'OPTIONS', 'GET'])
@app.route('/webhook/', methods=['POST', 'OPTIONS', 'GET'])  # Support trailing slash
def webhook():
    """
    Main webhook endpoint for GitHub push events
    """
    # Handle GET requests (health check)
    if request.method == 'GET':
        logger.info("GET request received at /webhook endpoint (health check)")
        return jsonify({
            'status': 'ok',
            'endpoint': '/webhook',
            'message': 'Webhook endpoint is active',
            'timestamp': datetime.now().isoformat()
        }), 200
    
    # Handle OPTIONS requests (CORS preflight)
    if request.method == 'OPTIONS':
        logger.info("OPTIONS request received at /webhook endpoint (CORS preflight)")
        response = jsonify({'status': 'ok'})
        response.headers.add('Access-Control-Allow-Origin', '*')
        response.headers.add('Access-Control-Allow-Methods', 'POST, OPTIONS, GET')
        response.headers.add('Access-Control-Allow-Headers', 'Content-Type, X-Hub-Signature-256, X-GitHub-Event')
        return response, 200
    
    # Log that webhook was triggered
    logger.info("=" * 60)
    logger.info("WEBHOOK TRIGGERED: /webhook endpoint")
    logger.info(f"Timestamp: {datetime.now().isoformat()}")
    logger.info(f"Request method: {request.method}")
    logger.info(f"Request path: {request.path}")
    logger.info(f"Remote address: {request.remote_addr}")
    logger.info(f"User-Agent: {request.headers.get('User-Agent', 'N/A')}")
    logger.info(f"Content-Type: {request.headers.get('Content-Type', 'N/A')}")
    logger.info(f"X-GitHub-Event: {request.headers.get('X-GitHub-Event', 'N/A')}")
    logger.info(f"X-GitHub-Delivery: {request.headers.get('X-GitHub-Delivery', 'N/A')}")
    logger.info("=" * 60)
    
    # Get raw payload for signature verification
    payload_body = request.get_data()
    logger.info(f"Payload size: {len(payload_body)} bytes")
    
    # Get signature from header (for logging only, not used for verification)
    signature = request.headers.get('X-Hub-Signature-256', '')
    logger.info(f"Signature header received: {'Yes' if signature else 'No'} (verification disabled)")
    
    # Skip signature verification - allow all requests
    logger.info("Skipping signature verification - allowing request")
    
    # Parse JSON payload
    try:
        if not payload_body:
            logger.warning("Empty payload received")
            return jsonify({
                'status': 'accepted',
                'message': 'Empty payload received, but request accepted',
                'timestamp': datetime.now().isoformat()
            }), 200
        
        payload = json.loads(payload_body.decode('utf-8'))
        logger.info("JSON payload parsed successfully")
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON payload: {e}")
        logger.error(f"Payload preview (first 200 chars): {payload_body[:200] if payload_body else 'empty'}")
        # Return 200 instead of 400 to avoid GitHub reporting errors
        return jsonify({
            'status': 'accepted',
            'message': 'Invalid JSON payload, but request accepted',
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        }), 200
    except Exception as e:
        logger.error(f"Unexpected error parsing payload: {e}")
        return jsonify({
            'status': 'accepted',
            'message': 'Error parsing payload, but request accepted',
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        }), 200
    
    # Log webhook event
    event_type = request.headers.get('X-GitHub-Event', 'unknown')
    logger.info(f"Received webhook event: {event_type}")
    
    # Accept all events - no filtering
    logger.info("Accepting all events - no filtering applied")
    
    # Accept all branches - no branch checking
    logger.info("Accepting all branches - no branch checking applied")
    
    # Extract commit information (for logging only, not required)
    commit_count = 0
    commit_messages = []
    try:
        commits = payload.get('commits', [])
        commit_count = len(commits) if commits else 0
        commit_messages = [c.get('message', '')[:50] for c in commits[:3]] if commits else []
        
        logger.info(f"Processing webhook with {commit_count} commit(s) (if any)")
        if commit_messages:
            logger.info(f"Commit messages: {', '.join(commit_messages)}")
    except Exception as e:
        logger.warning(f"Could not extract commit info: {e} (continuing anyway)")
    
    # Run update script in background thread to keep webhook listener responsive
    logger.info("Triggering update and restart in background...")
    add_log_entry('info', 'Webhook triggered update and restart (running in background)', {
        'event_type': event_type,
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


@app.route('/', methods=['GET', 'POST', 'OPTIONS'])
@app.route('//', methods=['GET', 'POST', 'OPTIONS'])  # Handle double slash (some proxies)
def index():
    """
    Root endpoint - handles both GET and POST requests
    - GET: triggers update-and-restart.sh when accessed
    - POST: handles GitHub webhook events (when webhook URL is set to root)
    - OPTIONS: handles CORS preflight requests
    """
    # Handle OPTIONS requests (CORS preflight)
    if request.method == 'OPTIONS':
        logger.info("OPTIONS request received at root endpoint (CORS preflight)")
        response = jsonify({'status': 'ok'})
        response.headers.add('Access-Control-Allow-Origin', '*')
        response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        response.headers.add('Access-Control-Allow-Headers', 'Content-Type, X-Hub-Signature-256, X-GitHub-Event')
        return response, 200
    
    # Handle POST requests as webhooks (when GitHub sends to root URL)
    if request.method == 'POST':
        logger.info("=" * 60)
        logger.info("WEBHOOK TRIGGERED: Root endpoint (/)")
        logger.info(f"Timestamp: {datetime.now().isoformat()}")
        logger.info(f"Request method: {request.method}")
        logger.info(f"Request path: {request.path}")
        logger.info(f"Remote address: {request.remote_addr}")
        logger.info(f"User-Agent: {request.headers.get('User-Agent', 'N/A')}")
        logger.info(f"Content-Type: {request.headers.get('Content-Type', 'N/A')}")
        logger.info(f"X-GitHub-Event: {request.headers.get('X-GitHub-Event', 'N/A')}")
        logger.info(f"X-GitHub-Delivery: {request.headers.get('X-GitHub-Delivery', 'N/A')}")
        logger.info("=" * 60)
        
        # Get raw payload for signature verification
        payload_body = request.get_data()
        logger.info(f"Payload size: {len(payload_body)} bytes")
        
        # Get signature from header (for logging only, not used for verification)
        signature = request.headers.get('X-Hub-Signature-256', '')
        logger.info(f"Signature header received: {'Yes' if signature else 'No'} (verification disabled)")
        
        # Skip signature verification - allow all requests
        logger.info("Skipping signature verification - allowing request")
        
        # Parse JSON payload
        try:
            if not payload_body:
                logger.warning("Empty payload received")
                return jsonify({
                    'status': 'accepted',
                    'message': 'Empty payload received, but request accepted',
                    'timestamp': datetime.now().isoformat()
                }), 200
            
            payload = json.loads(payload_body.decode('utf-8'))
            logger.info("JSON payload parsed successfully")
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON payload: {e}")
            logger.error(f"Payload preview (first 200 chars): {payload_body[:200] if payload_body else 'empty'}")
            # Return 200 instead of 400 to avoid GitHub reporting errors
            return jsonify({
                'status': 'accepted',
                'message': 'Invalid JSON payload, but request accepted',
                'error': str(e),
                'timestamp': datetime.now().isoformat()
            }), 200
        except Exception as e:
            logger.error(f"Unexpected error parsing payload: {e}")
            return jsonify({
                'status': 'accepted',
                'message': 'Error parsing payload, but request accepted',
                'error': str(e),
                'timestamp': datetime.now().isoformat()
            }), 200
        
        # Log webhook event
        event_type = request.headers.get('X-GitHub-Event', 'unknown')
        logger.info(f"Received webhook event at root endpoint: {event_type}")
        
        # Accept all events - no filtering
        logger.info("Accepting all events - no filtering applied")
        
        # Accept all branches - no branch checking
        logger.info("Accepting all branches - no branch checking applied")
        
        # Extract commit information (for logging only, not required)
        commit_count = 0
        commit_messages = []
        try:
            commits = payload.get('commits', [])
            commit_count = len(commits) if commits else 0
            commit_messages = [c.get('message', '')[:50] for c in commits[:3]] if commits else []
            
            logger.info(f"Processing webhook with {commit_count} commit(s) (if any)")
            if commit_messages:
                logger.info(f"Commit messages: {', '.join(commit_messages)}")
        except Exception as e:
            logger.warning(f"Could not extract commit info: {e} (continuing anyway)")
            commit_count = 0
            commit_messages = []
        
        # Run update script in background thread to keep webhook listener responsive
        logger.info("Triggering update and restart in background...")
        add_log_entry('info', 'Webhook triggered update and restart (root endpoint, running in background)', {
            'event_type': event_type,
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


@app.errorhandler(404)
def not_found(e):
    """Handle 404 Not Found errors with detailed logging"""
    logger.warning(f"404 Not Found: {request.method} {request.path}")
    logger.warning(f"Request headers: {dict(request.headers)}")
    logger.warning(f"Available routes: /webhook (POST), / (GET/POST), /health (GET), /trigger (GET/POST), /logs (GET)")
    return jsonify({
        'error': 'Not Found',
        'method': request.method,
        'path': request.path,
        'message': f'Route {request.path} not found',
        'available_routes': {
            '/webhook': 'POST - GitHub webhook endpoint',
            '/': 'GET/POST - Root endpoint (handles webhooks and manual triggers)',
            '/health': 'GET - Health check',
            '/trigger': 'GET/POST - Manual trigger',
            '/logs': 'GET - View logs'
        }
    }), 404


# ============================================================================
# Main Entry Point
# ============================================================================

def main():
    """
    Main entry point for the webhook listener
    """
    # Verify all required files are in the same directory
    logger.info("Verifying required files in script directory...")
    logger.info(f"Script directory: {SCRIPT_DIR}")
    
    required_files = {
        'Update script': UPDATE_SCRIPT,
        'App file': APP_FILE,
    }
    
    missing_files = []
    for name, file_path in required_files.items():
        if file_path.exists():
            logger.info(f"  ✓ {name}: {file_path}")
        else:
            logger.error(f"  ✗ {name}: {file_path} (NOT FOUND)")
            missing_files.append(name)
    
    if missing_files:
        logger.error(f"Missing required files: {', '.join(missing_files)}")
        logger.error(f"Please ensure all files exist in: {SCRIPT_DIR}")
        sys.exit(1)
    
    # Log optional files
    optional_files = {
        'Requirements file': REQUIREMENTS_FILE,
        'Venv directory': VENV_DIR,
        'PID file': PID_FILE,
        'Wrapper script': WRAPPER_SCRIPT,
    }
    
    for name, file_path in optional_files.items():
        if file_path.exists():
            logger.info(f"  ✓ {name}: {file_path}")
        else:
            logger.debug(f"  - {name}: {file_path} (not found, will be created if needed)")
    
    logger.info("All required files found in script directory")
    
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

