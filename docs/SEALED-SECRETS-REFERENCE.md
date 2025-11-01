## Sealed Secrets Summary

### What Gets Sealed

1. **Ring-MQTT Token** → `workload/apps/ring-mqtt/manifests/sealedsecret-ring-mqtt.yaml`
   - Env var: `RINGTOKEN`
   - Already referenced in deployment

2. **Home Assistant secrets.yaml** → `workload/apps/home-assistant/manifests/sealedsecret-secrets.yaml`
   - Mounted at: `/config/secrets.yaml`
   - Contains: IFTTT key, Google secure pin, etc.

3. **Google Assistant Service Account** → `workload/apps/home-assistant/manifests/sealedsecret-google.yaml`
   - Mounted at: `/config/SERVICE_ACCOUNT.json`
   - For Google Assistant integration

### Workflow

**Before deployment:**
```bash
# 1. Run sealing script
./scripts/seal-ha-secrets.sh

# 2. Verify sealed secrets created
ls -la workload/apps/ring-mqtt/manifests/sealedsecret-ring-mqtt.yaml
ls -la workload/apps/home-assistant/manifests/sealedsecret-secrets.yaml
ls -la workload/apps/home-assistant/manifests/sealedsecret-google.yaml

# 3. Uncomment sealed secret lines in kustomization.yaml files
sed -i '' 's/#   - manifests\/sealedsecret/  - manifests\/sealedsecret/g' \
  workload/apps/ring-mqtt/kustomization.yaml \
  workload/apps/home-assistant/kustomization.yaml

# 4. Commit and push
git add .
git commit -m "feat: add sealed secrets for home automation stack"
git push
```

**After deployment:**
- Sealed secrets controller will decrypt and create regular k8s secrets
- Ring-MQTT pod will read `RINGTOKEN` from env var
- Home Assistant pod will read files from mounted secrets

### Verification

```bash
# Check sealed secrets created in cluster
kubectl --context homeops get sealedsecrets -n home-automation

# Check decrypted secrets (DON'T output values!)
kubectl --context homeops get secrets -n home-automation

# Verify mounts in HA pod
kubectl --context homeops exec -n home-automation <ha-pod> -- ls -la /config/secrets.yaml
kubectl --context homeops exec -n home-automation <ha-pod> -- ls -la /config/SERVICE_ACCOUNT.json
```

