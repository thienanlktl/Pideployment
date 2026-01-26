#!/bin/bash
# ============================================================================
# Automatically Create GitHub Webhook
# ============================================================================
# This script automatically creates a GitHub webhook using the GitHub API
# No manual steps needed!
#
# Usage:
#   chmod +x create-github-webhook.sh
#   ./create-github-webhook.sh
#
# Requirements:
#   - GitHub Personal Access Token (with repo access)
#   - ngrok URL (from ./get-ngrok-url.sh)
#   - Webhook secret (from .webhook_secret file)
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
CYAN='\033[0;36m'
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

print_step() {
    echo ""
    echo -e "${CYAN}============================================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}============================================================================${NC}"
    echo ""
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$SCRIPT_DIR}"

# Configuration
GITHUB_USER="${GITHUB_USER:-thienanlktl}"
REPO_NAME="${REPO_NAME:-Pideployment}"
WEBHOOK_SECRET_FILE="$PROJECT_DIR/.webhook_secret"
NGROK_URL_FILE="$PROJECT_DIR/.ngrok_url"

# Hardcoded ngrok public URL for GitHub webhook setup
HARDCODED_NGROK_URL="https://tardy-vernita-howlingly.ngrok-free.dev"

echo ""
print_step "Automatically Create GitHub Webhook"

# ============================================================================
# Step 1: Get GitHub Personal Access Token
# ============================================================================
print_step "Step 1: GitHub Authentication"

# Check for token in environment variable
if [ -n "$GITHUB_TOKEN" ]; then
    print_info "Using GitHub token from environment variable"
    GITHUB_TOKEN="$GITHUB_TOKEN"
elif [ -f "$PROJECT_DIR/.github_token" ]; then
    GITHUB_TOKEN=$(cat "$PROJECT_DIR/.github_token" 2>/dev/null)
    if [ -n "$GITHUB_TOKEN" ]; then
        print_info "Using GitHub token from .github_token file"
    fi
fi

if [ -z "$GITHUB_TOKEN" ]; then
    # Check if running non-interactively (from setup script)
    if [ -n "$NON_INTERACTIVE" ]; then
        print_warning "GitHub token not provided and running non-interactively"
        print_info "Skipping webhook creation"
        exit 0
    fi
    
    print_info "GitHub Personal Access Token is required"
    print_info "Create one at: https://github.com/settings/tokens"
    print_info "Required scopes: repo (for private repos) or public_repo (for public repos)"
    echo ""
    read -p "Enter your GitHub Personal Access Token: " GITHUB_TOKEN
    
    if [ -z "$GITHUB_TOKEN" ]; then
        print_error "GitHub token is required"
        exit 1
    fi
    
    # Optionally save token
    read -p "Save token to .github_token file for future use? (y/n) " -n 1 -r
    echo ""
    case "$REPLY" in
        [Yy]*)
            echo "$GITHUB_TOKEN" > "$PROJECT_DIR/.github_token"
            chmod 600 "$PROJECT_DIR/.github_token"
            print_success "Token saved to .github_token (restricted permissions)"
            ;;
    esac
fi

# ============================================================================
# Step 2: Get Webhook URL
# ============================================================================
print_step "Step 2: Getting Webhook URL"

# Try to get ngrok URL
if [ -f "$NGROK_URL_FILE" ]; then
    WEBHOOK_URL=$(cat "$NGROK_URL_FILE" | tr -d '\n\r ')
    if [ -n "$WEBHOOK_URL" ]; then
        print_success "Found webhook URL: $WEBHOOK_URL"
    fi
fi

# If not found in file, try to get from ngrok API
if [ -z "$WEBHOOK_URL" ] && command -v curl >/dev/null 2>&1; then
    print_info "Getting ngrok URL from API..."
    # Try multiple ports to find ngrok API
    NGROK_BASE_URL=""
    for port in 4040 4041 4042 4043 4044; do
        if curl -s --max-time 2 "http://localhost:$port/api/tunnels" >/dev/null 2>&1; then
            NGROK_BASE_URL=$(curl -s --max-time 3 "http://localhost:$port/api/tunnels" 2>/dev/null | \
                grep -o '"public_url":"https://[^"]*' | head -1 | sed 's/"public_url":"//')
            if [ -n "$NGROK_BASE_URL" ]; then
                break
            fi
        fi
    done
    
    if [ -n "$NGROK_BASE_URL" ]; then
        # Ensure webhook URL has /webhook suffix
        if echo "$NGROK_BASE_URL" | grep -q "/webhook$"; then
            WEBHOOK_URL="$NGROK_BASE_URL"
        else
            WEBHOOK_URL="$NGROK_BASE_URL/webhook"
        fi
        print_success "Got webhook URL: $WEBHOOK_URL"
        echo "$WEBHOOK_URL" > "$NGROK_URL_FILE"
    fi
fi

# If still not found, use hardcoded URL
if [ -z "$WEBHOOK_URL" ] && [ -n "$HARDCODED_NGROK_URL" ]; then
    print_info "Using hardcoded ngrok URL: $HARDCODED_NGROK_URL"
    if echo "$HARDCODED_NGROK_URL" | grep -q "/webhook$"; then
        WEBHOOK_URL="$HARDCODED_NGROK_URL"
    else
        WEBHOOK_URL="$HARDCODED_NGROK_URL/webhook"
    fi
    print_success "Using hardcoded webhook URL: $WEBHOOK_URL"
    echo "$WEBHOOK_URL" > "$NGROK_URL_FILE"
fi

# If still not found and not in non-interactive mode, prompt
if [ -z "$WEBHOOK_URL" ]; then
    if [ -n "$NON_INTERACTIVE" ]; then
        print_error "Webhook URL not available and running non-interactively"
        print_info "Make sure ngrok is running and .ngrok_url file exists"
        exit 1
    fi
    
    print_warning "Could not get ngrok URL automatically"
    print_info "Run: ./get-ngrok-url.sh"
    echo ""
    read -p "Enter webhook URL (e.g., https://xxxx.ngrok.io/webhook): " WEBHOOK_URL
    
    if [ -z "$WEBHOOK_URL" ]; then
        print_error "Webhook URL is required"
        exit 1
    fi
fi

# ============================================================================
# Step 3: Get Webhook Secret
# ============================================================================
print_step "Step 3: Getting Webhook Secret"

if [ -f "$WEBHOOK_SECRET_FILE" ]; then
    WEBHOOK_SECRET=$(cat "$WEBHOOK_SECRET_FILE")
    print_success "Found webhook secret"
else
    print_warning "Webhook secret file not found: $WEBHOOK_SECRET_FILE"
    print_info "Run: ./setup-deployment-from-scratch.sh to generate secret"
    echo ""
    read -p "Enter webhook secret: " WEBHOOK_SECRET
    
    if [ -z "$WEBHOOK_SECRET" ]; then
        print_error "Webhook secret is required"
        exit 1
    fi
fi

# ============================================================================
# Step 4: Check if webhook already exists
# ============================================================================
print_step "Step 4: Checking Existing Webhooks"

print_info "Checking for existing webhooks..."
EXISTING_WEBHOOKS=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/$GITHUB_USER/$REPO_NAME/hooks" 2>/dev/null)

if echo "$EXISTING_WEBHOOKS" | grep -q "\"url\""; then
    print_info "Found existing webhooks"
    
    # Check if our webhook URL already exists
    if echo "$EXISTING_WEBHOOKS" | grep -q "$WEBHOOK_URL"; then
        print_warning "Webhook with this URL already exists"
        read -p "Update existing webhook? (y/n) " -n 1 -r
        echo ""
        case "$REPLY" in
            [Yy]*)
                UPDATE_EXISTING=true
                # Get webhook ID
                # Extract webhook ID (using sed for better compatibility)
                WEBHOOK_ID=$(echo "$EXISTING_WEBHOOKS" | grep -B 5 "$WEBHOOK_URL" | \
                    grep '"id"' | head -1 | sed 's/.*"id": *\([0-9]*\).*/\1/')
                ;;
            *)
                print_info "Keeping existing webhook"
                print_success "Webhook is already configured!"
                exit 0
                ;;
        esac
    else
        UPDATE_EXISTING=false
        print_info "Will create new webhook"
    fi
else
    UPDATE_EXISTING=false
    print_info "No existing webhooks found"
fi

# ============================================================================
# Step 5: Create or Update Webhook
# ============================================================================
print_step "Step 5: Creating/Updating Webhook"

# Prepare webhook payload
WEBHOOK_PAYLOAD=$(cat <<EOF
{
  "name": "web",
  "active": true,
  "events": ["push"],
  "config": {
    "url": "$WEBHOOK_URL",
    "content_type": "application/json",
    "secret": "$WEBHOOK_SECRET",
    "insecure_ssl": "0"
  }
}
EOF
)

if [ "$UPDATE_EXISTING" = true ] && [ -n "$WEBHOOK_ID" ]; then
    print_info "Updating existing webhook (ID: $WEBHOOK_ID)..."
    RESPONSE=$(curl -s -w "\n%{http_code}" -X PATCH \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        -d "$WEBHOOK_PAYLOAD" \
        "https://api.github.com/repos/$GITHUB_USER/$REPO_NAME/hooks/$WEBHOOK_ID" 2>/dev/null)
else
    print_info "Creating new webhook..."
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        -d "$WEBHOOK_PAYLOAD" \
        "https://api.github.com/repos/$GITHUB_USER/$REPO_NAME/hooks" 2>/dev/null)
fi

# Extract HTTP status code (last line)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

# Check response
if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "200" ]; then
    print_success "Webhook created/updated successfully!"
    echo ""
    print_info "Webhook Details:"
    echo "  URL: $WEBHOOK_URL"
    echo "  Events: push"
    echo "  Repository: $GITHUB_USER/$REPO_NAME"
    echo ""
    print_info "View webhook in GitHub:"
    echo "  https://github.com/$GITHUB_USER/$REPO_NAME/settings/hooks"
    echo ""
    print_success "Setup complete! Webhook will trigger on push to main branch."
else
    print_error "Failed to create/update webhook"
    print_error "HTTP Status: $HTTP_CODE"
    echo ""
    print_error "Response:"
    echo "$RESPONSE_BODY" | head -20
    echo ""
    print_info "Troubleshooting:"
    echo "  1. Verify GitHub token has correct permissions"
    echo "  2. Check webhook URL is accessible"
    echo "  3. Verify repository name: $GITHUB_USER/$REPO_NAME"
    exit 1
fi

echo ""

