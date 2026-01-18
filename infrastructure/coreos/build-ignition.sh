#!/usr/bin/env bash
set -euo pipefail

# Build ignition config from butane template
# Usage: ./build-ignition.sh <hostname> [output-dir]
#
# Requires:
#   - butane (brew install butane)
#   - K3S_TOKEN env var or .env file
#   - SSH public key at ~/.ssh/id_ed25519.pub (or set SSH_PUBKEY env var)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/agent-node.bu.template"

# Load .env if exists
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/.env"
fi

# Validate inputs
HOSTNAME="${1:-}"
OUTPUT_DIR="${2:-${SCRIPT_DIR}/output}"

if [[ -z "${HOSTNAME}" ]]; then
    echo "Usage: $0 <hostname> [output-dir]"
    echo ""
    echo "Environment variables:"
    echo "  K3S_TOKEN   - Cluster join token (required)"
    echo "  K3S_SERVER  - K3s server URL (required)"
    echo "  SSH_PUBKEY  - SSH public key (default: contents of ~/.ssh/id_ed25519.pub)"
    echo ""
    echo "You can also create a .env file in this directory with these variables."
    echo "See .env.example for the format."
    exit 1
fi

# Get K3S_TOKEN
if [[ -z "${K3S_TOKEN:-}" ]]; then
    echo "Error: K3S_TOKEN not set"
    echo ""
    echo "You can get it from an existing control-plane node:"
    echo "  ssh core@<master-node> 'sudo cat /var/lib/rancher/k3s/server/token'"
    echo ""
    echo "Then either:"
    echo "  export K3S_TOKEN='<token>'"
    echo "  or add it to ${SCRIPT_DIR}/.env"
    exit 1
fi

# Get K3S_SERVER
if [[ -z "${K3S_SERVER:-}" ]]; then
    echo "Error: K3S_SERVER not set"
    echo ""
    echo "Set it to your k3s control-plane node, e.g.:"
    echo "  export K3S_SERVER='https://<master-ip>:6443'"
    echo "  or add it to ${SCRIPT_DIR}/.env"
    exit 1
fi

# Get SSH public key
if [[ -z "${SSH_PUBKEY:-}" ]]; then
    SSH_KEY_FILE="${HOME}/.ssh/id_ed25519.pub"
    if [[ ! -f "${SSH_KEY_FILE}" ]]; then
        SSH_KEY_FILE="${HOME}/.ssh/id_rsa.pub"
    fi
    if [[ ! -f "${SSH_KEY_FILE}" ]]; then
        echo "Error: No SSH public key found. Set SSH_PUBKEY env var or create ~/.ssh/id_ed25519.pub"
        exit 1
    fi
    SSH_PUBKEY="$(cat "${SSH_KEY_FILE}")"
fi

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Generate butane config with substitutions
BUTANE_FILE="${OUTPUT_DIR}/${HOSTNAME}.bu"
IGNITION_FILE="${OUTPUT_DIR}/${HOSTNAME}.ign"

echo "Generating butane config for ${HOSTNAME}..."

sed -e "s|{{HOSTNAME}}|${HOSTNAME}|g" \
    -e "s|{{K3S_TOKEN}}|${K3S_TOKEN}|g" \
    -e "s|{{K3S_SERVER}}|${K3S_SERVER}|g" \
    -e "s|{{SSH_PUBKEY}}|${SSH_PUBKEY}|g" \
    "${TEMPLATE}" > "${BUTANE_FILE}"

echo "Transpiling to ignition..."

if ! command -v butane &> /dev/null; then
    echo "Error: butane not found. Install with: brew install butane"
    exit 1
fi

butane --strict "${BUTANE_FILE}" > "${IGNITION_FILE}"

echo ""
echo "Generated:"
echo "  Butane:   ${BUTANE_FILE}"
echo "  Ignition: ${IGNITION_FILE}"
echo ""
echo "Next steps:"
echo "  1. Serve the ignition file via HTTP, or"
echo "  2. Use it during CoreOS installation:"
echo ""
echo "     # From CoreOS live ISO:"
echo "     sudo coreos-installer install /dev/sda --ignition-url http://<your-server>/${HOSTNAME}.ign"
echo ""
echo "     # Or with local file:"
echo "     sudo coreos-installer install /dev/sda --ignition-file ${IGNITION_FILE}"
