#!/bin/bash
set -e

# ClawdBot Image Builder
# Builds and pushes ClawdBot container image from official GitHub releases
#
# Usage:
#   ./build-image.sh [VERSION]
#   ./build-image.sh v2026.1.16-2
#
# If no version is specified, uses the version from kustomization.yaml

VERSION=${1:-$(grep 'newTag:' kustomization.yaml | awk -F'"' '{print $2}')}
REGISTRY="ghcr.io/dels78"
IMAGE_NAME="clawdbot"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${VERSION}"
LATEST_IMAGE="${REGISTRY}/${IMAGE_NAME}:latest"

echo "Building ClawdBot ${VERSION}..."

# Clone ClawdBot repository
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

echo "Cloning ClawdBot repository..."
git clone --branch ${VERSION} --depth 1 https://github.com/clawdbot/clawdbot.git ${TEMP_DIR}

# Build Docker image
echo "Building image ${FULL_IMAGE}..."
cd ${TEMP_DIR}
docker build -t ${FULL_IMAGE} -t ${LATEST_IMAGE} .

# Push to registry
echo "Pushing image to registry..."
docker push ${FULL_IMAGE}
docker push ${LATEST_IMAGE}

echo "Successfully built and pushed:"
echo "  ${FULL_IMAGE}"
echo "  ${LATEST_IMAGE}"
echo ""
echo "Update kustomization.yaml if needed:"
echo "  newTag: \"${VERSION}\""
