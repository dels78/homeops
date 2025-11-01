#!/bin/bash
# Setup GitHub authentication for this project
set -e

# Check if .env.local exists
if [ ! -f .env.local ]; then
    echo "Error: .env.local not found"
    echo "Please create it with: echo 'GITHUB_USER=martindelisle' > .env.local"
    exit 1
fi

# Source the config
source .env.local

if [ -z "$GITHUB_USER" ]; then
    echo "Error: GITHUB_USER not set in .env.local"
    echo "Please edit .env.local and set your GitHub username"
    exit 1
fi

echo "Switching GitHub auth to $GITHUB_USER..."

# Check if user is already authenticated with gh
if ! gh auth status 2>&1 | grep -q "$GITHUB_USER"; then
    echo "Error: Not authenticated with gh CLI as $GITHUB_USER"
    echo ""
    echo "Please run: gh auth login"
    exit 1
fi

# Check if GITHUB_TOKEN env var is set (from Haus or other)
if [ -n "$GITHUB_TOKEN" ]; then
    echo "⚠️  GITHUB_TOKEN environment variable is set (probably from Haus)"
    echo "Unsetting it for this shell session..."
    unset GITHUB_TOKEN
fi

# Switch to the specified user
gh auth switch -u "$GITHUB_USER"

# Export the token from gh CLI
export GITHUB_TOKEN=$(gh auth token)

echo "✓ Switched to $GITHUB_USER"
echo "✓ GITHUB_TOKEN exported"
echo ""
echo "To use in your current shell, run:"
echo "  source scripts/setup-github-auth.sh"

