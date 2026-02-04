#!/usr/bin/env python3
"""
Update Service for IoT PubSub GUI
This script handles application updates and restart.
It is launched by the main application when user confirms an update.
"""

import sys
import os
import subprocess
import time
import logging
from pathlib import Path

# Configure logging
log_file = Path(__file__).parent / "update_service.log"
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(log_file),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

def get_venv_python(script_dir):
    """Get the virtual environment Python executable path"""
    venv_paths = [
        script_dir / "venv" / "bin" / "python3",
        script_dir / "venv" / "bin" / "python",
        script_dir / "venv" / "Scripts" / "python.exe",  # Windows
    ]
    
    for venv_path in venv_paths:
        if venv_path.exists():
            return venv_path
    return None

def wait_for_process_to_exit(process_name, timeout=30):
    """Wait for a process to exit"""
    logger.info(f"Waiting for {process_name} to exit...")
    start_time = time.time()
    
    while time.time() - start_time < timeout:
        try:
            # Check if process is still running (Linux/Mac)
            result = subprocess.run(
                ['pgrep', '-f', process_name],
                capture_output=True,
                text=True
            )
            if result.returncode != 0:
                logger.info(f"{process_name} has exited")
                return True
        except FileNotFoundError:
            # pgrep not available (Windows), try alternative
            try:
                result = subprocess.run(
                    ['tasklist', '/FI', f'IMAGENAME eq {process_name}'],
                    capture_output=True,
                    text=True
                )
                if process_name.lower() not in result.stdout.lower():
                    logger.info(f"{process_name} has exited")
                    return True
            except:
                # If we can't check, wait a bit and assume it's done
                time.sleep(2)
                return True
        
        time.sleep(0.5)
    
    logger.warning(f"Timeout waiting for {process_name} to exit")
    return False

def perform_update(target_version, script_dir):
    """Perform the application update"""
    try:
        logger.info("=" * 60)
        logger.info("Starting application update...")
        logger.info(f"Target version: {target_version}")
        logger.info(f"Script directory: {script_dir}")
        
        release_branch = f"Release/{target_version}"
        logger.info(f"Target release branch: {release_branch}")
        
        # Step 1: Wait a moment for main app to fully shutdown
        logger.info("Waiting for main application to shutdown...")
        time.sleep(2)
        
        # Step 2: Fetch latest changes
        logger.info("Fetching latest changes from repository...")
        result = subprocess.run(
            ['git', 'fetch', 'origin'],
            cwd=script_dir,
            capture_output=True,
            text=True,
            timeout=30
        )
        if result.returncode != 0:
            raise Exception(f"git fetch failed: {result.stderr}")
        
        # Step 3: Checkout the Release branch
        logger.info(f"Checking out {release_branch}...")
        result = subprocess.run(
            ['git', 'checkout', release_branch],
            cwd=script_dir,
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if result.returncode != 0:
            # Branch doesn't exist locally, create it from remote
            logger.info(f"Creating local branch {release_branch} from remote...")
            result = subprocess.run(
                ['git', 'checkout', '-b', release_branch, f'origin/{release_branch}'],
                cwd=script_dir,
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.returncode != 0:
                raise Exception(f"git checkout failed: {result.stderr}")
        
        # Step 4: Pull latest changes
        logger.info(f"Pulling latest code from {release_branch}...")
        result = subprocess.run(
            ['git', 'pull', 'origin', release_branch],
            cwd=script_dir,
            capture_output=True,
            text=True,
            timeout=30
        )
        if result.returncode != 0:
            # Fallback to reset if pull fails
            logger.info("Pull failed, using reset instead...")
            result = subprocess.run(
                ['git', 'reset', '--hard', f'origin/{release_branch}'],
                cwd=script_dir,
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.returncode != 0:
                raise Exception(f"git pull/reset failed: {result.stderr}")
        
        logger.info(f"Code updated successfully to {release_branch}")
        
        # Step 5: Install/upgrade dependencies
        logger.info("Verifying and installing Python dependencies...")
        
        venv_python = get_venv_python(script_dir)
        if not venv_python:
            logger.warning("Virtual environment not found, creating one...")
            try:
                result = subprocess.run(
                    [sys.executable, '-m', 'venv', str(script_dir / "venv")],
                    cwd=script_dir,
                    capture_output=True,
                    text=True,
                    timeout=60
                )
                if result.returncode == 0:
                    venv_python = get_venv_python(script_dir)
                    logger.info(f"Created virtual environment: {venv_python}")
            except Exception as e:
                logger.warning(f"Could not create venv: {e}")
        
        if not venv_python:
            venv_python = Path(sys.executable)
            logger.warning(f"Using system Python: {venv_python}")
        
        requirements_file = script_dir / "requirements.txt"
        if not requirements_file.exists():
            raise Exception(f"requirements.txt not found at {requirements_file}")
        
        logger.info(f"Installing dependencies from {requirements_file}...")
        logger.info(f"Using Python: {venv_python}")
        
        # Upgrade pip
        logger.info("Upgrading pip...")
        result = subprocess.run(
            [str(venv_python), '-m', 'pip', 'install', '--upgrade', 'pip'],
            cwd=script_dir,
            capture_output=True,
            text=True,
            timeout=60
        )
        if result.returncode != 0:
            logger.warning(f"pip upgrade had issues: {result.stderr}")
        else:
            logger.info("pip upgraded successfully")
        
        # Install/upgrade all requirements
        logger.info("Installing/upgrading all required packages...")
        result = subprocess.run(
            [str(venv_python), '-m', 'pip', 'install', '-r', str(requirements_file), '--upgrade'],
            cwd=script_dir,
            capture_output=True,
            text=True,
            timeout=600
        )
        
        if result.returncode != 0:
            error_output = result.stderr or result.stdout
            raise Exception(f"Failed to install dependencies: {error_output}")
        
        logger.info("Package installation completed")
        
        # Verify key packages
        logger.info("Verifying key dependencies...")
        key_packages = ['PyQt6', 'awsiotsdk', 'awscrt', 'requests', 'cryptography']
        all_verified = True
        for package in key_packages:
            result = subprocess.run(
                [str(venv_python), '-m', 'pip', 'show', package],
                cwd=script_dir,
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.returncode == 0:
                version_line = [line for line in result.stdout.split('\n') if line.startswith('Version:')]
                version = version_line[0].split(':')[1].strip() if version_line else 'unknown'
                logger.info(f"  ✓ {package} installed (version: {version})")
            else:
                logger.error(f"  ✗ {package} NOT FOUND")
                all_verified = False
        
        if not all_verified:
            raise Exception("Some required packages were not installed correctly")
        
        logger.info("All dependencies verified and installed successfully")
        logger.info("=" * 60)
        
        return venv_python
        
    except Exception as e:
        logger.error(f"Update failed: {e}")
        raise

def restart_application(venv_python, script_dir):
    """Restart the main application"""
    try:
        logger.info("Preparing to restart application...")
        
        script_path = script_dir / "iot_pubsub_gui.py"
        if not script_path.exists():
            raise Exception(f"Script not found: {script_path}")
        
        # Verify Python environment
        logger.info("Verifying Python environment before restart...")
        test_result = subprocess.run(
            [str(venv_python), '-c', 'import awscrt; import PyQt6; print("OK")'],
            cwd=script_dir,
            capture_output=True,
            text=True,
            timeout=10
        )
        if test_result.returncode == 0:
            logger.info("Python environment verified successfully")
        else:
            logger.warning(f"Python environment test failed: {test_result.stderr}")
        
        # Change to script directory
        os.chdir(script_dir)
        
        # Start the application
        logger.info(f"Starting application: {venv_python} {script_path}")
        logger.info("=" * 60)
        
        # Use subprocess.Popen to start in background and detach
        if sys.platform == 'win32':
            # Windows
            subprocess.Popen(
                [str(venv_python), str(script_path)],
                cwd=str(script_dir),
                creationflags=subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS
            )
        else:
            # Linux/Mac
            subprocess.Popen(
                [str(venv_python), str(script_path)],
                cwd=str(script_dir),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True
            )
        
        logger.info("Application restarted successfully")
        time.sleep(1)  # Give it a moment to start
        
    except Exception as e:
        logger.error(f"Failed to restart application: {e}")
        raise

def main():
    """Main entry point"""
    if len(sys.argv) < 3:
        logger.error("Usage: update_service.py <target_version> <script_dir>")
        sys.exit(1)
    
    target_version = sys.argv[1]
    script_dir = Path(sys.argv[2]).absolute()
    
    if not script_dir.exists():
        logger.error(f"Script directory does not exist: {script_dir}")
        sys.exit(1)
    
    try:
        # Perform update
        venv_python = perform_update(target_version, script_dir)
        
        # Restart application
        restart_application(venv_python, script_dir)
        
        logger.info("Update service completed successfully")
        sys.exit(0)
        
    except Exception as e:
        logger.error(f"Update service failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()

