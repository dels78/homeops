#!/usr/bin/env bash
# Run these commands in your terminal (where kubeseal alias works)

set -e

cd /Users/martindelisle/code/personal/homeops

echo "🔐 Creating Sealed Secrets..."
echo ""

# 1. Ring-MQTT Token
echo "📱 Ring-MQTT Token"
RING_TOKEN="eyJhbGciOiJSUzI1NiIsImprdSI6Ii9vYXV0aC9pbnRlcm5hbC9qd2tzIiwia2lkIjoiNGRjODQyZGIiLCJ0eXAiOiJKV1QifQ.eyJpYXQiOjE2ODU3Mjc3MzIsImlzcyI6IlJpbmdPYXV0aFNlcnZpY2UtcHJvZDp1cy1lYXN0LTE6NDgxZGRkNmUiLCJyZWZyZXNoX2NpZCI6InJpbmdfb2ZmaWNpYWxfYW5kcm9pZCIsInJlZnJlc2hfc2NvcGVzIjpbImNsaWVudCJdLCJyZWZyZXNoX3VzZXJfaWQiOjY4Nzg0NTIsInJuZCI6ImZlZUx1c1JIeUwiLCJzZXNzaW9uX2lkIjoiNjMzNDBmYjUtMDY2NS00NmIzLTkyNGQtYjJjZmY4ZjJjMDVmIiwidHlwZSI6InJlZnJlc2gtdG9rZW4ifQ.mJwgWbVKFRuHj2kYvkwsFO0ynnSR8xoexXgGiNl4HL7tpEic12VA-JXGiprEGsvUbuaS2i6oohfOvfjxt_u61ghjgg23GkaMDUy3GFzBLfZRrZH_VHGhqNx-FXKzp480cQBUXfCySraVybyCsYtY7SqUM51ao1EvxvEkK3KL5NrK8IuFUd14sZ3_LBfHa-aUJx8uPiV6GbeYylQDBWEyYjVbOfWPMLVahohFD11__JiDVHm_AcenrTSr_U_yjajlMeW1v0T2oFLXi8SuubSFJ7Vsn-6GJO30fp_bnfJNF-euWn9WtHgIq30i11chMKWxiIJj4zB_VL9Uq64Brp8buA"

kubectl create secret generic ring-mqtt-secret \
  --from-literal=ring-token="$RING_TOKEN" \
  --namespace=home-automation \
  --dry-run=client -o yaml | \
  kubeseal \
  > workload/apps/ring-mqtt/manifests/sealedsecret-ring-mqtt.yaml

echo "✅ Created: workload/apps/ring-mqtt/manifests/sealedsecret-ring-mqtt.yaml"
echo ""

# 2. Home Assistant secrets.yaml
echo "🏠 Home Assistant secrets.yaml"
kubectl create secret generic home-assistant-secrets \
  --from-file=secrets.yaml=/Volumes/Backup/dockerbian/homeassistant/secrets.yaml \
  --namespace=home-automation \
  --dry-run=client -o yaml | \
  kubeseal \
  > workload/apps/home-assistant/manifests/sealedsecret-secrets.yaml

echo "✅ Created: workload/apps/home-assistant/manifests/sealedsecret-secrets.yaml"
echo ""

# 3. Google Assistant Service Account
echo "🔑 Google Assistant Service Account"
kubectl create secret generic home-assistant-google \
  --from-file=SERVICE_ACCOUNT.json=/Volumes/Backup/dockerbian/homeassistant/SERVICE_ACCOUNT.json \
  --namespace=home-automation \
  --dry-run=client -o yaml | \
  kubeseal \
  > workload/apps/home-assistant/manifests/sealedsecret-google.yaml

echo "✅ Created: workload/apps/home-assistant/manifests/sealedsecret-google.yaml"
echo ""

echo "✅ All sealed secrets created!"
echo ""
echo "Next: Uncomment sealed secret lines in kustomization.yaml files"

