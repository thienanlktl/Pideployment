#!/bin/bash
# ============================================================================
# Test Deployment Setup
# ============================================================================
# This script tests various components of the deployment system
#
# Usage:
#   chmod +x test-deployment.sh
#   ./test-deployment.sh
# ============================================================================

# Detect if running with sh and re-execute with bash if needed
if [ -z "$BASH_VERSION" ]; then
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    else
        echo "Error: This script requires bash." >&2
        exit 1
    fi
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo "============================================================================"
echo "Deployment System Test"
echo "============================================================================"
echo ""

TESTS_PASSED=0
TESTS_FAILED=0

# Test 1: Check if required files exist
print_info "Test 1: Checking required files..."
REQUIRED_FILES=(
    "update-and-restart.sh"
    "webhook_listener.py"
    "iot-gui-webhook.service"
    "setup-ssh-key.sh"
    "requirements.txt"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$SCRIPT_DIR/$file" ]; then
        print_success "$file exists"
        ((TESTS_PASSED++))
    else
        print_error "$file not found"
        ((TESTS_FAILED++))
    fi
done

# Test 2: Check if scripts are executable
print_info ""
print_info "Test 2: Checking script permissions..."
SCRIPTS=(
    "update-and-restart.sh"
    "setup-ssh-key.sh"
)

for script in "${SCRIPTS[@]}"; do
    if [ -x "$SCRIPT_DIR/$script" ]; then
        print_success "$script is executable"
        ((TESTS_PASSED++))
    else
        print_warning "$script is not executable (run: chmod +x $script)"
        ((TESTS_FAILED++))
    fi
done

# Test 3: Check if virtual environment exists
print_info ""
print_info "Test 3: Checking virtual environment..."
if [ -d "$SCRIPT_DIR/venv" ]; then
    print_success "Virtual environment exists"
    ((TESTS_PASSED++))
    
    # Check if Flask is installed
    if "$SCRIPT_DIR/venv/bin/python" -c "import flask" 2>/dev/null; then
        print_success "Flask is installed in venv"
        ((TESTS_PASSED++))
    else
        print_warning "Flask not found in venv (run: pip install Flask)"
        ((TESTS_FAILED++))
    fi
else
    print_warning "Virtual environment not found (run: ./setup-and-run.sh first)"
    ((TESTS_FAILED++))
fi

# Test 4: Check git repository
print_info ""
print_info "Test 4: Checking git repository..."
if [ -d "$SCRIPT_DIR/.git" ]; then
    print_success "Git repository found"
    ((TESTS_PASSED++))
    
    # Check git remote
    GIT_REMOTE=$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null || echo "")
    if [ -n "$GIT_REMOTE" ]; then
        print_success "Git remote configured: $GIT_REMOTE"
        ((TESTS_PASSED++))
        
        # Check if remote is SSH
        if echo "$GIT_REMOTE" | grep -q "git@github.com"; then
            print_success "Git remote uses SSH"
            ((TESTS_PASSED++))
        else
            print_warning "Git remote doesn't use SSH (recommended: git@github.com:...)"
            ((TESTS_FAILED++))
        fi
    else
        print_warning "No git remote 'origin' configured"
        ((TESTS_FAILED++))
    fi
else
    print_warning "Not a git repository"
    ((TESTS_FAILED++))
fi

# Test 5: Check SSH key
print_info ""
print_info "Test 5: Checking SSH key..."
SSH_KEY="$SCRIPT_DIR/id_ed25519_repo_pideployment"
if [ -f "$SSH_KEY" ]; then
    print_success "SSH key exists: $SSH_KEY"
    ((TESTS_PASSED++))
    
    # Check permissions
    PERMS=$(stat -c "%a" "$SSH_KEY" 2>/dev/null || stat -f "%OLp" "$SSH_KEY" 2>/dev/null || echo "unknown")
    if [ "$PERMS" = "600" ]; then
        print_success "SSH key has correct permissions (600)"
        ((TESTS_PASSED++))
    else
        print_warning "SSH key permissions: $PERMS (should be 600)"
        ((TESTS_FAILED++))
    fi
else
    print_warning "SSH key not found in current directory: $SSH_KEY (run: ./setup-ssh-key.sh)"
    ((TESTS_FAILED++))
fi

# Test 6: Check webhook listener syntax
print_info ""
print_info "Test 6: Checking webhook listener..."
if "$SCRIPT_DIR/venv/bin/python" -m py_compile "$SCRIPT_DIR/webhook_listener.py" 2>/dev/null; then
    print_success "webhook_listener.py syntax is valid"
    ((TESTS_PASSED++))
else
    print_error "webhook_listener.py has syntax errors"
    ((TESTS_FAILED++))
fi

# Test 7: Check systemd service (if exists)
print_info ""
print_info "Test 7: Checking systemd service..."
if systemctl list-unit-files | grep -q "iot-gui-webhook.service"; then
    print_success "Systemd service is installed"
    ((TESTS_PASSED++))
    
    # Check service status
    if systemctl is-active --quiet iot-gui-webhook.service 2>/dev/null; then
        print_success "Systemd service is running"
        ((TESTS_PASSED++))
    else
        print_warning "Systemd service is not running (run: sudo systemctl start iot-gui-webhook.service)"
        ((TESTS_FAILED++))
    fi
else
    print_info "Systemd service not installed (optional)"
fi

# Test 8: Check if port 9000 is available/listening
print_info ""
print_info "Test 8: Checking webhook port..."
if command -v netstat >/dev/null 2>&1; then
    if netstat -tuln 2>/dev/null | grep -q ":9000"; then
        print_success "Port 9000 is in use (webhook listener may be running)"
        ((TESTS_PASSED++))
    else
        print_info "Port 9000 is available"
    fi
elif command -v ss >/dev/null 2>&1; then
    if ss -tuln 2>/dev/null | grep -q ":9000"; then
        print_success "Port 9000 is in use (webhook listener may be running)"
        ((TESTS_PASSED++))
    else
        print_info "Port 9000 is available"
    fi
fi

# Summary
echo ""
echo "============================================================================"
echo "Test Summary"
echo "============================================================================"
echo ""
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    print_success "All tests passed! Deployment system is ready."
    exit 0
else
    print_warning "Some tests failed. Please review the output above."
    print_info "Most issues can be fixed by:"
    echo "  1. Running: ./setup-ssh-key.sh"
    echo "  2. Running: ./setup-and-run.sh (to create venv)"
    echo "  3. Installing Flask: source venv/bin/activate && pip install Flask"
    echo "  4. Making scripts executable: chmod +x *.sh"
    exit 1
fi

