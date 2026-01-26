#!/bin/bash
# ============================================================================
# Quick ngrok Setup with Pre-configured Token
# ============================================================================
# This script sets up ngrok using the provided authtoken
#
# Usage:
#   chmod +x setup-ngrok-with-token.sh
#   ./setup-ngrok-with-token.sh
# ============================================================================

# Your ngrok authtoken (pre-configured)
NGROK_AUTHTOKEN="38HbghqIwfeBRpp4wdZHFkeTOT1_2Dh6671w4NZEUoFMpcVa6"

# Export for use by setup-ngrok.sh
export NGROK_AUTHTOKEN

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Run the main setup script with the token
"$SCRIPT_DIR/setup-ngrok.sh" "$NGROK_AUTHTOKEN"

