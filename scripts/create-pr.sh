#!/bin/bash
# Create PR for current branch
set -e

# Ensure we're on a feature branch
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" = "main" ]; then
    echo "Error: Cannot create PR from main branch"
    exit 1
fi

echo ""
echo "Creating PR..."

# Get the PR title and body from the last commit
PR_TITLE=$(git log -1 --pretty=%s)
PR_BODY=$(git log -1 --pretty=%b)

# Create the PR via CLI
gh pr create \
    --title "$PR_TITLE" \
    --body "$PR_BODY" \
    --base main \
    --head "$CURRENT_BRANCH"

echo ""
echo "✓ PR created"

