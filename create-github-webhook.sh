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
#   - GitHub Personal Access Token (hardcoded in script, or from env/file)
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

# Hardcoded GitHub Personal Access Token
HARDCODED_GITHUB_TOKEN="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"

echo ""
print_step "Automatically Create GitHub Webhook"

# ============================================================================
# Step 1: Get GitHub Personal Access Token
# ============================================================================
print_step "Step 1: GitHub Authentication"

# Check for token: environment variable, hardcoded token, or .github_token file
if [ -n "$GITHUB_TOKEN" ]; then
    print_info "Using GitHub token from environment variable"
    GITHUB_TOKEN="$GITHUB_TOKEN"
elif [ -n "$HARDCODED_GITHUB_TOKEN" ]; then
    GITHUB_TOKEN="$HARDCODED_GITHUB_TOKEN"
    print_info "Using hardcoded GitHub token"
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
# Step 4: Verify GitHub Token and Repository Access
# ============================================================================
print_step "Step 4: Verifying GitHub Access"

print_info "Verifying GitHub token and repository access..."
AUTH_CHECK=$(curl -s -w "\n%{http_code}" -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/$GITHUB_USER/$REPO_NAME" 2>/dev/null)

AUTH_HTTP_CODE=$(echo "$AUTH_CHECK" | tail -1)
AUTH_RESPONSE_BODY=$(echo "$AUTH_CHECK" | sed '$d')

if [ "$AUTH_HTTP_CODE" != "200" ]; then
    print_error "Failed to access repository"
    print_error "HTTP Status: $AUTH_HTTP_CODE"
    if echo "$AUTH_RESPONSE_BODY" | grep -q "Bad credentials"; then
        print_error "Invalid GitHub token or token expired"
        print_info "Create a new token at: https://github.com/settings/tokens"
    elif echo "$AUTH_RESPONSE_BODY" | grep -q "Not Found"; then
        print_error "Repository not found: $GITHUB_USER/$REPO_NAME"
        print_info "Verify repository name and that token has access"
    else
        print_error "Response: $(echo "$AUTH_RESPONSE_BODY" | head -5)"
    fi
    exit 1
fi

print_success "GitHub token is valid and has repository access"

# ============================================================================
# Step 5: Check if webhook already exists
# ============================================================================
print_step "Step 5: Checking Existing Webhooks"

print_info "Checking for existing webhooks..."
EXISTING_WEBHOOKS_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/$GITHUB_USER/$REPO_NAME/hooks" 2>/dev/null)

EXISTING_WEBHOOKS_HTTP_CODE=$(echo "$EXISTING_WEBHOOKS_RESPONSE" | tail -1)
EXISTING_WEBHOOKS=$(echo "$EXISTING_WEBHOOKS_RESPONSE" | sed '$d')

if [ "$EXISTING_WEBHOOKS_HTTP_CODE" != "200" ]; then
    print_warning "Could not check existing webhooks (HTTP $EXISTING_WEBHOOKS_HTTP_CODE)"
    print_info "Will attempt to create new webhook"
    UPDATE_EXISTING=false
    WEBHOOK_ID=""
elif echo "$EXISTING_WEBHOOKS" | grep -q "\"id\""; then
    print_info "Found existing webhooks"
    
    # Check if our webhook URL already exists
    # Escape the URL for grep
    ESCAPED_WEBHOOK_URL=$(echo "$WEBHOOK_URL" | sed 's/[[\.*^$()+?{|]/\\&/g')
    if echo "$EXISTING_WEBHOOKS" | grep -q "$ESCAPED_WEBHOOK_URL"; then
        print_warning "Webhook with this URL already exists"
        
        # Extract webhook ID more reliably using JSON parsing
        # Try using Python if available for better JSON parsing
        if command -v python3 >/dev/null 2>&1; then
            WEBHOOK_ID=$(echo "$EXISTING_WEBHOOKS" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for hook in data:
        if hook.get('config', {}).get('url') == sys.argv[1]:
            print(hook['id'])
            sys.exit(0)
except:
    pass
" "$WEBHOOK_URL" 2>/dev/null)
        fi
        
        # Fallback to grep/sed if Python not available
        if [ -z "$WEBHOOK_ID" ]; then
            WEBHOOK_ID=$(echo "$EXISTING_WEBHOOKS" | grep -A 10 "$ESCAPED_WEBHOOK_URL" | \
                grep '"id"' | head -1 | sed 's/.*"id": *\([0-9]*\).*/\1/')
        fi
        
        if [ -n "$WEBHOOK_ID" ] && [ "$NON_INTERACTIVE" != "1" ]; then
            read -p "Update existing webhook (ID: $WEBHOOK_ID)? (y/n) " -n 1 -r
            echo ""
            case "$REPLY" in
                [Yy]*)
                    UPDATE_EXISTING=true
                    ;;
                *)
                    print_info "Keeping existing webhook"
                    print_success "Webhook is already configured!"
                    exit 0
                    ;;
            esac
        elif [ -n "$WEBHOOK_ID" ]; then
            # Non-interactive mode - auto-update
            UPDATE_EXISTING=true
            print_info "Auto-updating existing webhook (ID: $WEBHOOK_ID) in non-interactive mode"
        else
            print_warning "Could not extract webhook ID, will create new webhook"
            UPDATE_EXISTING=false
        fi
    else
        UPDATE_EXISTING=false
        print_info "Will create new webhook"
    fi
else
    UPDATE_EXISTING=false
    print_info "No existing webhooks found"
fi

# ============================================================================
# Step 6: Create or Update Webhook
# ============================================================================
print_step "Step 6: Creating/Updating Webhook"

# Validate webhook URL format
if ! echo "$WEBHOOK_URL" | grep -qE "^https?://"; then
    print_error "Invalid webhook URL format: $WEBHOOK_URL"
    print_info "URL must start with http:// or https://"
    exit 1
fi

# Prepare webhook payload (escape quotes in URL and secret)
ESCAPED_WEBHOOK_URL=$(echo "$WEBHOOK_URL" | sed 's/"/\\"/g')
ESCAPED_WEBHOOK_SECRET=$(echo "$WEBHOOK_SECRET" | sed 's/"/\\"/g')

WEBHOOK_PAYLOAD=$(cat <<EOF
{
  "name": "web",
  "active": true,
  "events": ["push"],
  "config": {
    "url": "$ESCAPED_WEBHOOK_URL",
    "content_type": "application/json",
    "secret": "$ESCAPED_WEBHOOK_SECRET",
    "insecure_ssl": "0"
  }
}
EOF
)

# Debug: Show what we're sending (without secret)
print_info "Webhook configuration:"
echo "  URL: $WEBHOOK_URL"
echo "  Events: push"
echo "  Repository: $GITHUB_USER/$REPO_NAME"
echo ""

if [ "$UPDATE_EXISTING" = true ] && [ -n "$WEBHOOK_ID" ]; then
    print_info "Updating existing webhook (ID: $WEBHOOK_ID)..."
    API_URL="https://api.github.com/repos/$GITHUB_USER/$REPO_NAME/hooks/$WEBHOOK_ID"
    HTTP_METHOD="PATCH"
else
    print_info "Creating new webhook..."
    API_URL="https://api.github.com/repos/$GITHUB_USER/$REPO_NAME/hooks"
    HTTP_METHOD="POST"
fi

# Make API request with better error handling
print_info "Sending request to GitHub API..."
RESPONSE=$(curl -s -w "\n%{http_code}" -X "$HTTP_METHOD" \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Content-Type: application/json" \
    -d "$WEBHOOK_PAYLOAD" \
    "$API_URL" 2>&1)

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
    if [ -n "$WEBHOOK_ID" ]; then
        echo "  Webhook ID: $WEBHOOK_ID"
    fi
    echo ""
    print_info "View webhook in GitHub:"
    echo "  https://github.com/$GITHUB_USER/$REPO_NAME/settings/hooks"
    echo ""
    print_success "Setup complete! Webhook will trigger on push to main branch."
    exit 0
else
    print_error "Failed to create/update webhook"
    print_error "HTTP Status: $HTTP_CODE"
    echo ""
    print_error "API Response:"
    echo "$RESPONSE_BODY" | head -30
    echo ""
    
    # Provide specific error messages
    if echo "$RESPONSE_BODY" | grep -qi "Bad credentials\|Unauthorized"; then
        print_error "Authentication failed - token is invalid or expired"
        print_info "Create a new token at: https://github.com/settings/tokens"
        print_info "Required scope: repo (for private) or public_repo (for public)"
    elif echo "$RESPONSE_BODY" | grep -qi "Not Found"; then
        print_error "Repository not found or no access"
        print_info "Verify: $GITHUB_USER/$REPO_NAME"
        print_info "Ensure token has access to this repository"
    elif echo "$RESPONSE_BODY" | grep -qi "Validation Failed\|Invalid"; then
        print_error "Validation error - check webhook URL format"
        print_info "URL must be accessible and start with http:// or https://"
        print_info "Current URL: $WEBHOOK_URL"
    elif echo "$RESPONSE_BODY" | grep -qi "Forbidden"; then
        print_error "Access forbidden - token may not have admin permissions"
        print_info "Token needs 'admin:repo_hook' scope for webhook management"
    else
        print_info "Troubleshooting:"
        echo "  1. Verify GitHub token has correct permissions (repo or admin:repo_hook)"
        echo "  2. Check webhook URL is accessible: curl -I $WEBHOOK_URL"
        echo "  3. Verify repository name: $GITHUB_USER/$REPO_NAME"
        echo "  4. Check token hasn't expired"
    fi
    exit 1
fi

echo ""

