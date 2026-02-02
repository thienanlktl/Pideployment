"""
Auto-update module for iot-pubsub-gui application.

This module handles:
- Version detection from git branches or VERSION file
- Fetching and comparing release branch versions
- Safe update execution with error handling
"""

import subprocess
import os
import sys
import shutil
from pathlib import Path
from datetime import datetime
from typing import Optional, Tuple, List
import logging

try:
    from packaging import version
    PACKAGING_AVAILABLE = True
except ImportError:
    PACKAGING_AVAILABLE = False
    logging.warning("packaging library not available. Version comparison will be limited.")

logger = logging.getLogger(__name__)


class UpdateError(Exception):
    """Custom exception for update-related errors"""
    pass


def get_current_version(repo_path: Path) -> Optional[str]:
    """
    Detect current version from multiple sources (in order of preference):
    1. Current git branch name (if it starts with 'release/')
    2. VERSION file
    3. Git describe --tags
    4. Git branch name (any branch)
    
    Returns:
        Version string (e.g., "1.0.0") or None if not found
    """
    repo_path = Path(repo_path).resolve()
    
    # Method 1: Check current git branch
    try:
        result = subprocess.run(
            ['git', 'rev-parse', '--abbrev-ref', 'HEAD'],
            cwd=repo_path,
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            branch_name = result.stdout.strip()
            if branch_name.startswith('release/'):
                version_str = branch_name.replace('release/', '').strip()
                if version_str:
                    logger.info(f"Detected version from branch: {version_str}")
                    return version_str
    except Exception as e:
        logger.debug(f"Could not get git branch: {e}")
    
    # Method 2: Read VERSION file
    version_file = repo_path / "VERSION"
    if version_file.exists():
        try:
            with open(version_file, 'r') as f:
                version_str = f.read().strip()
                if version_str:
                    logger.info(f"Detected version from VERSION file: {version_str}")
                    return version_str
        except Exception as e:
            logger.debug(f"Could not read VERSION file: {e}")
    
    # Method 3: Git describe --tags
    try:
        result = subprocess.run(
            ['git', 'describe', '--tags', '--always'],
            cwd=repo_path,
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            describe_output = result.stdout.strip()
            # Try to extract version from tag (e.g., "v1.0.0" or "1.0.0")
            version_str = describe_output.lstrip('v').split('-')[0]
            if version_str:
                logger.info(f"Detected version from git describe: {version_str}")
                return version_str
    except Exception as e:
        logger.debug(f"Could not get git describe: {e}")
    
    # Method 4: Any git branch name (fallback)
    try:
        result = subprocess.run(
            ['git', 'rev-parse', '--abbrev-ref', 'HEAD'],
            cwd=repo_path,
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            branch_name = result.stdout.strip()
            logger.info(f"Using branch name as version (fallback): {branch_name}")
            return branch_name
    except Exception as e:
        logger.debug(f"Could not get git branch: {e}")
    
    logger.warning("Could not detect version from any source")
    return None


def fetch_remote_branches(repo_path: Path) -> bool:
    """
    Fetch all remote branches and prune stale references.
    
    Returns:
        True if successful, False otherwise
    """
    repo_path = Path(repo_path).resolve()
    
    try:
        logger.info("Fetching remote branches...")
        result = subprocess.run(
            ['git', 'fetch', '--all', '--prune'],
            cwd=repo_path,
            capture_output=True,
            text=True,
            timeout=30
        )
        
        if result.returncode == 0:
            logger.info("Successfully fetched remote branches")
            return True
        else:
            logger.error(f"git fetch failed: {result.stderr}")
            return False
    except subprocess.TimeoutExpired:
        logger.error("git fetch timed out")
        return False
    except Exception as e:
        logger.error(f"Error fetching remote branches: {e}")
        return False


def get_release_branches(repo_path: Path) -> List[Tuple[str, str]]:
    """
    Get all remote release branches matching pattern origin/release/*
    and extract their versions.
    
    Returns:
        List of tuples: [(version_string, branch_name), ...]
        Example: [("1.0.0", "origin/release/1.0.0"), ("1.0.1", "origin/release/1.0.1")]
    """
    repo_path = Path(repo_path).resolve()
    release_branches = []
    
    try:
        # Get all remote branches
        result = subprocess.run(
            ['git', 'branch', '-r'],
            cwd=repo_path,
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if result.returncode != 0:
            logger.error(f"Failed to list remote branches: {result.stderr}")
            return release_branches
        
        # Filter for release branches
        for line in result.stdout.split('\n'):
            line = line.strip()
            if line.startswith('origin/release/'):
                branch_name = line
                version_str = branch_name.replace('origin/release/', '').strip()
                if version_str:
                    release_branches.append((version_str, branch_name))
        
        logger.info(f"Found {len(release_branches)} release branches")
        return release_branches
        
    except Exception as e:
        logger.error(f"Error getting release branches: {e}")
        return release_branches


def find_latest_version(repo_path: Path) -> Optional[Tuple[str, str]]:
    """
    Find the latest (highest) version among all release branches.
    
    Returns:
        Tuple of (version_string, branch_name) or None if no releases found
        Example: ("1.0.1", "origin/release/1.0.1")
    """
    release_branches = get_release_branches(repo_path)
    
    if not release_branches:
        logger.warning("No release branches found")
        return None
    
    # Sort versions using packaging library if available
    if PACKAGING_AVAILABLE:
        try:
            # Sort by version (highest first)
            sorted_branches = sorted(
                release_branches,
                key=lambda x: version.parse(x[0]),
                reverse=True
            )
            latest = sorted_branches[0]
            logger.info(f"Latest version found: {latest[0]} ({latest[1]})")
            return latest
        except Exception as e:
            logger.warning(f"Error parsing versions with packaging: {e}. Using string comparison.")
    
    # Fallback: Simple string comparison (less reliable)
    try:
        sorted_branches = sorted(release_branches, key=lambda x: x[0], reverse=True)
        latest = sorted_branches[0]
        logger.info(f"Latest version found (string comparison): {latest[0]} ({latest[1]})")
        return latest
    except Exception as e:
        logger.error(f"Error sorting versions: {e}")
        return None


def compare_versions(current: str, latest: str) -> int:
    """
    Compare two version strings.
    
    Returns:
        -1 if current < latest (update available)
         0 if current == latest (up to date)
         1 if current > latest (ahead of latest, unusual)
    """
    if not PACKAGING_AVAILABLE:
        # Fallback: simple string comparison
        if current < latest:
            return -1
        elif current > latest:
            return 1
        else:
            return 0
    
    try:
        current_ver = version.parse(current)
        latest_ver = version.parse(latest)
        
        if current_ver < latest_ver:
            return -1
        elif current_ver > latest_ver:
            return 1
        else:
            return 0
    except Exception as e:
        logger.warning(f"Error comparing versions: {e}. Using string comparison.")
        if current < latest:
            return -1
        elif current > latest:
            return 1
        else:
            return 0


def has_uncommitted_changes(repo_path: Path) -> bool:
    """
    Check if there are uncommitted changes in the repository.
    
    Returns:
        True if there are uncommitted changes, False otherwise
    """
    repo_path = Path(repo_path).resolve()
    
    try:
        result = subprocess.run(
            ['git', 'status', '--porcelain'],
            cwd=repo_path,
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode == 0:
            return bool(result.stdout.strip())
        else:
            # If git status fails, assume there might be changes (safer)
            logger.warning("git status failed, assuming there might be uncommitted changes")
            return True
    except Exception as e:
        logger.warning(f"Error checking for uncommitted changes: {e}")
        return True  # Assume there are changes to be safe


def create_backup(repo_path: Path) -> Optional[Path]:
    """
    Create a backup of the current repository directory.
    
    Returns:
        Path to backup directory or None if backup failed
    """
    repo_path = Path(repo_path).resolve()
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_name = f"backup_{timestamp}"
    backup_path = repo_path.parent / backup_name
    
    try:
        logger.info(f"Creating backup to: {backup_path}")
        shutil.copytree(repo_path, backup_path, ignore=shutil.ignore_patterns('.git'))
        logger.info("Backup created successfully")
        return backup_path
    except Exception as e:
        logger.error(f"Failed to create backup: {e}")
        return None


def perform_update(
    repo_path: Path,
    target_branch: str,
    update_dependencies: bool = True,
    create_backup_before_update: bool = True
) -> Tuple[bool, str]:
    """
    Perform the update by checking out the target release branch.
    
    Args:
        repo_path: Path to the repository
        target_branch: Branch name to checkout (e.g., "origin/release/1.0.1")
        update_dependencies: Whether to update pip dependencies
        create_backup_before_update: Whether to create a backup before updating
    
    Returns:
        Tuple of (success: bool, message: str)
    """
    repo_path = Path(repo_path).resolve()
    
    # Check for uncommitted changes
    if has_uncommitted_changes(repo_path):
        return False, "Cannot update: There are uncommitted changes in the repository. Please commit or stash them first."
    
    # Create backup if requested
    backup_path = None
    if create_backup_before_update:
        backup_path = create_backup(repo_path)
        if backup_path is None:
            logger.warning("Backup creation failed, but continuing with update")
    
    try:
        # Step 1: Fetch latest changes
        logger.info("Fetching latest changes...")
        result = subprocess.run(
            ['git', 'fetch', 'origin'],
            cwd=repo_path,
            capture_output=True,
            text=True,
            timeout=30
        )
        if result.returncode != 0:
            return False, f"git fetch failed: {result.stderr}"
        
        # Step 2: Extract branch name without 'origin/' prefix for checkout
        # We need to checkout the local branch name
        branch_name = target_branch.replace('origin/', '')
        
        # Step 3: Checkout the target branch
        logger.info(f"Checking out branch: {branch_name}")
        result = subprocess.run(
            ['git', 'checkout', branch_name],
            cwd=repo_path,
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode != 0:
            # If branch doesn't exist locally, create it tracking the remote
            logger.info(f"Branch doesn't exist locally, creating tracking branch...")
            result = subprocess.run(
                ['git', 'checkout', '-b', branch_name, target_branch],
                cwd=repo_path,
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.returncode != 0:
                return False, f"git checkout failed: {result.stderr}"
        
        # Step 4: Reset to match remote exactly
        logger.info(f"Resetting to {target_branch}...")
        result = subprocess.run(
            ['git', 'reset', '--hard', target_branch],
            cwd=repo_path,
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode != 0:
            return False, f"git reset failed: {result.stderr}"
        
        # Step 5: Update dependencies if requested
        if update_dependencies:
            logger.info("Updating Python dependencies...")
            requirements_file = repo_path / "requirements.txt"
            if requirements_file.exists():
                # Try to use venv python if available
                venv_python = repo_path / "venv" / "bin" / "python3"
                if not venv_python.exists():
                    # Try Windows venv path
                    venv_python = repo_path / "venv" / "Scripts" / "python.exe"
                if not venv_python.exists():
                    venv_python = sys.executable
                
                result = subprocess.run(
                    [str(venv_python), '-m', 'pip', 'install', '-r', 'requirements.txt', '--upgrade'],
                    cwd=repo_path,
                    capture_output=True,
                    text=True,
                    timeout=300
                )
                if result.returncode != 0:
                    logger.warning(f"pip upgrade had warnings: {result.stderr}")
                    # Don't fail the update if pip has warnings
            else:
                logger.info("No requirements.txt found, skipping dependency update")
        
        success_msg = f"Update completed successfully!"
        if backup_path:
            success_msg += f"\nBackup created at: {backup_path}"
        
        return True, success_msg
        
    except subprocess.TimeoutExpired:
        return False, "Update timed out. Please try again."
    except Exception as e:
        error_msg = f"Update failed: {str(e)}"
        logger.error(error_msg)
        return False, error_msg


def check_for_updates(repo_path: Path) -> Optional[Tuple[str, str, str]]:
    """
    Check for available updates by comparing current version with latest release branch.
    
    Returns:
        Tuple of (current_version, latest_version, latest_branch) if update available,
        None if up to date or error occurred
    """
    repo_path = Path(repo_path).resolve()
    
    # Get current version
    current_version = get_current_version(repo_path)
    if not current_version:
        logger.warning("Could not determine current version")
        return None
    
    # Fetch remote branches
    if not fetch_remote_branches(repo_path):
        logger.warning("Failed to fetch remote branches")
        return None
    
    # Find latest version
    latest_info = find_latest_version(repo_path)
    if not latest_info:
        logger.warning("No release branches found")
        return None
    
    latest_version, latest_branch = latest_info
    
    # Compare versions
    comparison = compare_versions(current_version, latest_version)
    if comparison < 0:
        logger.info(f"Update available: {current_version} -> {latest_version}")
        return (current_version, latest_version, latest_branch)
    elif comparison == 0:
        logger.info("Application is up to date")
        return None
    else:
        logger.info(f"Current version ({current_version}) is ahead of latest ({latest_version})")
        return None

