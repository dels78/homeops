# Pre-Deployment Checklist

Complete these steps **before** committing and deploying:

## ✅ Infrastructure Ready

- [x] USB dongles connected to minipc.dels.local
- [x] generic-device-plugin exposing `squat.ai/serial: 2`
- [x] NFS permissions updated for k3s node IPs
- [x] Traefik IngressRoute at home.dels.info exists

## 📦 Data Preparation

- [ ] Home Assistant backup at `/volume1/homeassistant` on Synology (192.168.1.252)
  ```bash
  # Verify or copy:
  ssh [user]@192.168.1.252 "ls -la /volume1/homeassistant/"
  
  # If needed, restore:
  rsync -avP /Volumes/Backup/dockerbian/homeassistant/ \
    [user]@192.168.1.252:/volume1/homeassistant/
  ```

- [ ] Ring-MQTT data (if preserving state):
  ```bash
  # Optional - Ring-MQTT can start fresh
  # If you want to preserve state:
  # Copy from: /Volumes/Backup/dockerbian/home/dels/src/dockerFiles/ring-mqtt/
  ```

## 🔐 Seal Secrets

- [ ] Run sealing script:
  ```bash
  cd /Users/martindelisle/code/personal/homeops
  ./scripts/seal-ha-secrets.sh
  ```

- [ ] Verify sealed secret files created:
  ```bash
  ls -la workload/apps/ring-mqtt/manifests/sealedsecret-ring-mqtt.yaml
  ls -la workload/apps/home-assistant/manifests/sealedsecret-secrets.yaml
  ls -la workload/apps/home-assistant/manifests/sealedsecret-google.yaml
  ```

- [ ] Uncomment sealed secret lines:
  ```bash
  sed -i '' 's/#   - manifests\/sealedsecret/  - manifests\/sealedsecret/g' \
    workload/apps/ring-mqtt/kustomization.yaml \
    workload/apps/home-assistant/kustomization.yaml
  ```

## 📝 Final Review

- [ ] Review git diff:
  ```bash
  git diff
  git status
  ```

- [ ] Verify kustomization files:
  ```bash
  # Should show sealed secret lines uncommented
  grep -n "sealedsecret" workload/apps/*/kustomization.yaml
  ```

## 🚀 Ready to Deploy

Once all above are complete:

```bash
git add .
git commit -m "feat: migrate Home Assistant to k3s cluster

- Add Mosquitto, ZWaveJS2MQTT, Ring-MQTT, Home Assistant
- Reuse existing home.dels.info Traefik route
- Use direct NFS mount for HA config
- Configure USB device passthrough
- Add sealed secrets for sensitive data"

git push origin feature/home-assistant-migration
```

Then:
1. Create PR on GitHub
2. Review and merge (Haus protocol: no direct commits to main)
3. Watch ArgoCD sync: `kubectl --context homeops get applications -n argocd -w`
4. Monitor pods: `kubectl --context homeops get pods -n home-automation -w`

## 🎯 Post-Deployment

See full guide: `docs/MIGRATION-HOME-ASSISTANT.md`

Quick checks:
```bash
# All pods running
kubectl --context homeops get pods -n home-automation

# Access HA
open https://home.dels.info

# Configure integrations (ZWave, Zigbee, Ring)
# See Phase 4 in migration guide
```

