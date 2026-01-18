#!/bin/bash
set -euo pipefail

# ClawdBot Image Builder
# Builds and pushes ClawdBot container image from official GitHub releases
#
# Usage:
#   ./build-image.sh [VERSION]
#   ./build-image.sh v2026.1.16-2
#
# If no version is specified, uses the version from kustomization.yaml

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

VERSION=${1:-$(grep 'newTag:' "${SCRIPT_DIR}/kustomization.yaml" | awk -F'"' '{print $2}')}
REGISTRY="ghcr.io/dels78"
IMAGE_NAME="clawdbot"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${VERSION}"
LATEST_IMAGE="${REGISTRY}/${IMAGE_NAME}:latest"

echo "Building ClawdBot ${VERSION}..."

# Setup GitHub authentication for personal account (multi-account safe)
echo "Setting up GitHub authentication..."
if [ -f "${REPO_ROOT}/scripts/setup-github-auth.sh" ]; then
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/scripts/setup-github-auth.sh"
else
  echo "Warning: setup-github-auth.sh not found, using existing gh auth"
fi

# Authenticate to GitHub Container Registry
if [ -n "${GITHUB_TOKEN:-}" ]; then
  echo "Authenticating to ghcr.io..."
  echo "${GITHUB_TOKEN}" | docker login ghcr.io -u dels78 --password-stdin
else
  echo "Warning: GITHUB_TOKEN not set, attempting docker login with existing credentials"
fi

# Clone ClawdBot repository
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

echo "Cloning ClawdBot repository..."
git clone --branch "${VERSION}" --depth 1 https://github.com/clawdbot/clawdbot.git "${TEMP_DIR}"

# Workaround: Dockerfile references patches directory that doesn't exist
# Create it if missing to avoid build failure
cd "${TEMP_DIR}"
if [ ! -d "patches" ]; then
  echo "Creating empty patches directory (workaround for Dockerfile bug)..."
  mkdir -p patches
fi

# Inject custom development tools into Dockerfile
echo "Injecting development tools into Dockerfile..."
cat >> Dockerfile << 'EOF'

# Custom development tools for autonomous coding
# Added by build-image.sh for homeops deployment

# Install system packages for development
RUN apt-get update && apt-get install -y \
  # Git & build tools
  git \
  # JSON/data processing
  jq \
  # Build tools
  build-essential \
  # Python development
  python3 \
  python3-pip \
  python3-venv \
  # Network tools
  curl \
  wget \
  # Linters
  shellcheck \
  # Dependencies for gh CLI
  ca-certificates \
  gnupg \
  && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI (gh) using official method
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
  && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
  && apt-get update \
  && apt-get install -y gh \
  && rm -rf /var/lib/apt/lists/*

# Install Python-based code quality tools
RUN pip3 install --no-cache-dir --break-system-packages \
  pre-commit \
  black \
  ruff \
  mypy \
  yamllint

EOF

# Build Docker image
echo "Building image ${FULL_IMAGE}..."
docker build --platform linux/amd64 -t "${FULL_IMAGE}" -t "${LATEST_IMAGE}" .

# Push to registry
echo "Pushing image to registry..."
docker push "${FULL_IMAGE}"
docker push "${LATEST_IMAGE}"

echo ""
echo "✓ Successfully built and pushed:"
echo "  ${FULL_IMAGE}"
echo "  ${LATEST_IMAGE}"
echo ""
echo "Update kustomization.yaml if needed:"
echo "  newTag: \"${VERSION}\""
