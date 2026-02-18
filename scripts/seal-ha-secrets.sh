#!/usr/bin/env bash
set -euo pipefail

# Script to create sealed secrets for Home Assistant migration
# Requires: kubeseal CLI tool and kubectl access to homeops cluster

CONTEXT="homeops"
NAMESPACE="home-automation"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔐 Home Assistant Secrets Sealing Script"
echo "========================================"
echo ""

# Check prerequisites
if ! kubectl --context "$CONTEXT" cluster-info &> /dev/null; then
    echo "❌ Error: Cannot access cluster with context: $CONTEXT"
    exit 1
fi

# Try kubeseal (check if it's a function/alias or actual command)
if ! type kubeseal &> /dev/null; then
    echo "❌ Error: kubeseal not found. Install it first:"
    echo "   brew install kubeseal"
    exit 1
fi

echo "✅ Prerequisites check passed"
echo ""

# Ring-MQTT Token
echo "📱 Ring-MQTT Token"
echo "------------------"
read -sp "Enter Ring refresh token (from backup or Ring web UI): " RING_TOKEN
echo ""

if [ -z "$RING_TOKEN" ]; then
    echo "❌ Ring token cannot be empty"
    exit 1
fi

echo "Creating sealed secret for ring-mqtt..."
kubectl create secret generic ring-mqtt-secret \
  --from-literal=ring-token="$RING_TOKEN" \
  --namespace="$NAMESPACE" \
  --dry-run=client -o yaml | \
  command kubeseal --controller-name sealed-secrets --controller-namespace kube-system --format yaml \
  > "$SCRIPT_DIR/../workload/apps/ring-mqtt/manifests/sealedsecret-ring-mqtt.yaml"

echo "✅ Created: workload/apps/ring-mqtt/manifests/sealedsecret-ring-mqtt.yaml"
echo ""

# Home Assistant secrets.yaml
echo "🏠 Home Assistant Secrets"
echo "-------------------------"
echo "This will seal your entire secrets.yaml file."
echo "Make sure you have your secrets.yaml ready."
echo ""

SECRETS_FILE="${SECRETS_FILE:-/Volumes/Backup/dockerbian/homeassistant/secrets.yaml}"

if [ ! -f "$SECRETS_FILE" ]; then
    echo "⚠️  Secrets file not found at: $SECRETS_FILE"
    read -p "Enter path to your secrets.yaml: " SECRETS_FILE

    if [ ! -f "$SECRETS_FILE" ]; then
        echo "❌ File not found: $SECRETS_FILE"
        exit 1
    fi
fi

echo "Using secrets from: $SECRETS_FILE"

kubectl create secret generic home-assistant-secrets \
  --from-file=secrets.yaml="$SECRETS_FILE" \
  --namespace="$NAMESPACE" \
  --dry-run=client -o yaml | \
  command kubeseal --controller-name sealed-secrets --controller-namespace kube-system --format yaml \
  > "$SCRIPT_DIR/../workload/apps/home-assistant/manifests/sealedsecret-secrets.yaml"

echo "✅ Created: workload/apps/home-assistant/manifests/sealedsecret-secrets.yaml"
echo ""

# Google Assistant service account
echo "🔑 Google Assistant Service Account"
echo "------------------------------------"

SERVICE_ACCOUNT_FILE="${SERVICE_ACCOUNT_FILE:-/Volumes/Backup/dockerbian/homeassistant/SERVICE_ACCOUNT.json}"

if [ ! -f "$SERVICE_ACCOUNT_FILE" ]; then
    echo "⚠️  Service account file not found at: $SERVICE_ACCOUNT_FILE"
    read -p "Enter path to your SERVICE_ACCOUNT.json: " SERVICE_ACCOUNT_FILE

    if [ ! -f "$SERVICE_ACCOUNT_FILE" ]; then
        echo "⚠️  Skipping Google Assistant service account (file not found)"
        SERVICE_ACCOUNT_FILE=""
    fi
fi

if [ -n "$SERVICE_ACCOUNT_FILE" ]; then
    echo "Using service account from: $SERVICE_ACCOUNT_FILE"

    kubectl create secret generic home-assistant-google \
      --from-file=SERVICE_ACCOUNT.json="$SERVICE_ACCOUNT_FILE" \
      --namespace="$NAMESPACE" \
      --dry-run=client -o yaml | \
      command kubeseal --controller-name sealed-secrets --controller-namespace kube-system --format yaml \
      > "$SCRIPT_DIR/../workload/apps/home-assistant/manifests/sealedsecret-google.yaml"

    echo "✅ Created: workload/apps/home-assistant/manifests/sealedsecret-google.yaml"
    echo ""
fi

echo "✅ All sealed secrets created successfully!"
echo ""
echo "Next steps:"
echo "1. Review the sealed secrets in workload/apps/*/manifests/"
echo "2. Uncomment the sealed secret resources in kustomization.yaml files"
echo "3. Commit and push to trigger ArgoCD sync"
