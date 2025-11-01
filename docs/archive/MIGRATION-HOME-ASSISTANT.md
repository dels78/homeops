# Home Assistant Migration to K3S Cluster

## Overview

Migration from standalone server to k3s homeops cluster for Home Assistant and related services.

**Status:** Ready for deployment
**Date:** November 1, 2025
**Branch:** `feature/home-assistant-migration`

## Services Being Deployed

1. **Mosquitto** - MQTT broker for Ring-MQTT and Home Assistant
2. **ZWaveJS2MQTT** - Z-Wave device management (USB: usb-0658_0200-if00)
3. **Ring-MQTT** - Ring alarm sensors bridge
4. **Home Assistant** - Main automation hub (USB: Nabu Casa SkyConnect)

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    home-automation                       │
│                      (namespace)                         │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  ┌──────────────┐    ┌──────────────┐                   │
│  │ Home         │◄──►│ Mosquitto    │◄────┐            │
│  │ Assistant    │    │ (MQTT)       │     │            │
│  │              │    └──────────────┘     │            │
│  │ - SkyConnect │                         │            │
│  │ - Zigbee     │    ┌──────────────┐     │            │
│  │ - Matter     │    │ ZWaveJS2MQTT │     │            │
│  └──────┬───────┘    │              │     │            │
│         │            │ - Z-Wave USB │     │            │
│         │            │ - WebSocket  │     │            │
│         │            └──────────────┘     │            │
│         │                                 │            │
│    [Ingress]           ┌──────────────┐   │            │
│ ha.delisle.me          │ Ring-MQTT    │───┘            │
│                        │              │                │
│                        │ - Ring API   │                │
│                        │ - MQTT pub   │                │
│                        └──────────────┘                │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

**Communication:**
- Home Assistant ↔ Mosquitto: MQTT (mosquitto.home-automation.svc.cluster.local:1883)
- Home Assistant ↔ ZWaveJS: WebSocket (zwavejs2mqtt.home-automation.svc.cluster.local:3000)
- Ring-MQTT → Mosquitto: MQTT publish
- External access: Home Assistant via home.dels.info (existing Traefik IngressRoute)

## Prerequisites

### USB Devices
✅ Both dongles connected to `minipc.dels.local` node:
- `/dev/serial/by-id/usb-0658_0200-if00` → Z-Wave stick
- `/dev/serial/by-id/usb-Nabu_Casa_SkyConnect_v1.0_a6ddb807bf18ec11adeeee9a47486eb0-if00-port0` → Zigbee/Matter

✅ generic-device-plugin exposing devices: `squat.ai/serial: 2`

### Backups
- Home Assistant config: `/Volumes/Backup/dockerbian/homeassistant/`
- Docker configs: `/Volumes/Backup/dockerbian/home/dels/src/dockerFiles/`
- Secrets: `secrets.yaml`, `SERVICE_ACCOUNT.json`, Ring token

### Tools Required
```bash
# kubeseal for creating sealed secrets
brew install kubeseal

# kubectl with homeops context
kubectl --context homeops cluster-info

# Optional: verify USB devices on node
ssh core@minipc.dels.local "ls -la /dev/serial/by-id/"
```

## Migration Steps

### Phase 1: Seal Secrets (Before Deployment)

**Run the sealing script:**
```bash
cd /Users/martindelisle/code/personal/homeops
./scripts/seal-ha-secrets.sh
```

The script will:
1. Prompt for Ring refresh token (from backup: `/Volumes/Backup/dockerbian/home/dels/src/dockerFiles/ring-mqtt/compose.yml`)
2. Seal Home Assistant secrets.yaml
3. Seal Google Assistant SERVICE_ACCOUNT.json
4. Create SealedSecret manifests in respective workload directories

**Manual alternative:**
```bash
# Ring token
kubectl create secret generic ring-mqtt-secret \
  --from-literal=ring-token="YOUR_RING_TOKEN" \
  --namespace=home-automation \
  --dry-run=client -o yaml | \
  kubeseal --controller-namespace sealed-secrets --format=yaml \
  > workload/apps/ring-mqtt/manifests/sealedsecret-ring-mqtt.yaml

# HA secrets
kubectl create secret generic home-assistant-secrets \
  --from-file=secrets.yaml=/Volumes/Backup/dockerbian/homeassistant/secrets.yaml \
  --namespace=home-automation \
  --dry-run=client -o yaml | \
  kubeseal --controller-namespace sealed-secrets --format=yaml \
  > workload/apps/home-assistant/manifests/sealedsecret-secrets.yaml
```

**Enable sealed secrets in kustomization:**
```bash
# After sealing, uncomment the sealed secret lines in:
# - workload/apps/ring-mqtt/kustomization.yaml (line 13)
# - workload/apps/home-assistant/kustomization.yaml (lines 12-13)

# Quick way:
sed -i '' 's/#   - manifests\/sealedsecret/  - manifests\/sealedsecret/g' \
  workload/apps/ring-mqtt/kustomization.yaml \
  workload/apps/home-assistant/kustomization.yaml
```

### Phase 2: Deploy Services

**Commit and push:**
```bash
git add .
git commit -m "feat: migrate Home Assistant to k3s cluster

- Add Mosquitto MQTT broker
- Add ZWaveJS2MQTT with Z-Wave USB device
- Add Ring-MQTT bridge for Ring sensors
- Add Home Assistant with SkyConnect USB device
- Configure USB device passthrough via generic-device-plugin
- Set nodeSelector to minipc.dels.local for USB access
- Configure hostNetwork for HA mDNS discovery
- Add ArgoCD applications for all services
- Create sealed secrets for sensitive data

Services communicate internally via k8s services.
Only Home Assistant exposed via ha.delisle.me."

git push origin feature/home-assistant-migration
```

**Create pull request and merge** (Haus protocol: no direct commits to main)

**Monitor ArgoCD sync:**
```bash
# Watch ArgoCD applications
kubectl --context homeops get applications -n argocd | grep -E "mosquitto|zwavejs|ring|home-assistant"

# Check deployment status
kubectl --context homeops get pods -n home-automation -w

# Check sync waves (mosquitto first, then zwavejs/ring, then HA)
# - Wave 0: mosquitto
# - Wave 1: zwavejs2mqtt, ring-mqtt
# - Wave 2: home-assistant
```

### Phase 3: Restore Home Assistant Config

Your Home Assistant data should be at `/volume1/homeassistant` on your Synology NAS (192.168.1.252).

**Option A: Data already there** (from previous backup):
- If your backup is already at `/volume1/homeassistant`, you're done!
- HA pod will mount it directly when it starts

**Option B: Restore from backup location**:
```bash
# SSH to Synology or use your preferred method to copy data
# From: /Volumes/Backup/dockerbian/homeassistant/
# To: 192.168.1.252:/volume1/homeassistant/

# Example using rsync (adjust paths as needed):
rsync -avP /Volumes/Backup/dockerbian/homeassistant/ \
  your-synology-user@192.168.1.252:/volume1/homeassistant/

# Or if mounted locally:
rsync -avP /Volumes/Backup/dockerbian/homeassistant/ \
  /Volumes/homeassistant/
```

The HA deployment uses direct NFS mount to `/volume1/homeassistant`, so data must be there before the pod starts.

### Phase 4: Configure Integrations

**ZWave JS:**
1. Access ZWaveJS UI: `kubectl --context homeops port-forward -n home-automation svc/zwavejs2mqtt 8091:8091`
2. Open http://localhost:8091
3. Configure Z-Wave controller: `/dev/serial/by-id/usb-0658_0200-if00` (should auto-detect)
4. Verify Z-Wave network is discovered

**Home Assistant ZWave Integration:**
1. Access HA: https://home.dels.info (via Cloudflare Zero Trust)
2. Settings → Devices & Services → Add Integration → Z-Wave
3. Server: `ws://zwavejs2mqtt.home-automation.svc.cluster.local:3000`
4. Verify devices appear

**Zigbee/Matter (SkyConnect):**
1. Settings → Devices & Services → Add Integration → Zigbee Home Automation (ZHA)
2. Radio Type: Select SkyConnect
3. Device Path: Should auto-detect the USB device
4. Verify Zigbee network forms

**Ring Integration (via MQTT):**
1. Ring-MQTT should auto-connect to Mosquitto
2. Check logs: `kubectl --context homeops logs -n home-automation -l app.kubernetes.io/name=ring-mqtt`
3. In HA: Settings → Devices & Services → MQTT
4. Configure: `mosquitto.home-automation.svc.cluster.local:1883`
5. Ring devices should auto-discover via MQTT

**MQTT Broker:**
- Already configured in HA via secrets.yaml
- Verify connection: Developer Tools → MQTT

## Validation Checklist

### Infrastructure
- [ ] All pods running: `kubectl --context homeops get pods -n home-automation`
- [ ] NFS mounts working: Check HA pod can access /config
- [ ] Services created: `kubectl --context homeops get svc -n home-automation`

### USB Devices
- [ ] Generic device plugin healthy: `kubectl --context homeops get daemonset -n default generic-device-plugin`
- [ ] Devices allocated on minipc: `kubectl --context homeops describe node minipc.dels.local | grep serial`
- [ ] ZWaveJS sees Z-Wave stick: Check /dev in zwavejs2mqtt pod
- [ ] HA sees SkyConnect: Check /dev in home-assistant pod

### Networking
- [ ] Mosquitto accessible internally: `kubectl --context homeops run -it --rm debug --image=busybox --restart=Never -- nc -zv mosquitto.home-automation.svc.cluster.local 1883`
- [ ] ZWaveJS WebSocket accessible: Test from HA pod
- [ ] Home Assistant accessible externally: https://home.dels.info

### Functionality
- [ ] Home Assistant UI loads
- [ ] Existing automations visible
- [ ] Z-Wave devices online
- [ ] Zigbee devices online
- [ ] Ring sensors reporting
- [ ] MQTT integration working
- [ ] Google Assistant responding
- [ ] Automations firing correctly

### Data
- [ ] Configuration restored
- [ ] History preserved
- [ ] Entities match previous setup
- [ ] Secrets loaded correctly

## Troubleshooting

### USB Device Not Found
```bash
# Check devices on node
ssh core@minipc.dels.local "ls -la /dev/serial/by-id/"

# Check generic-device-plugin logs
kubectl --context homeops logs -n default -l app=generic-device-plugin

# Verify resource allocation
kubectl --context homeops describe pod -n home-automation <pod-name> | grep -A 5 "Limits:"
```

### Pod Stuck in Pending
```bash
# Check events
kubectl --context homeops describe pod -n home-automation <pod-name>

# Common issues:
# - NFS mount failed (check NFS server accessibility and permissions)
# - USB device not available (check node resources)
# - Node selector mismatch (must be minipc.dels.local for USB pods)

# Verify NFS accessibility from node
ssh core@minipc.dels.local "showmount -e 192.168.1.252"
```

### Ring-MQTT Not Connecting
```bash
# Check logs
kubectl --context homeops logs -n home-automation -l app.kubernetes.io/name=ring-mqtt

# Common issues:
# - Invalid Ring token (refresh it via Ring web UI)
# - Cannot reach Mosquitto (check service: mosquitto.home-automation.svc.cluster.local)

# Test Ring token manually
kubectl --context homeops port-forward -n home-automation svc/ring-mqtt 55123:55123
# Open http://localhost:55123 to regenerate token
```

### ZWaveJS Not Starting
```bash
# Check USB device permissions
kubectl --context homeops exec -it -n home-automation <zwavejs-pod> -- ls -la /dev/

# Check logs
kubectl --context homeops logs -n home-automation -l app.kubernetes.io/name=zwavejs2mqtt

# Common issues:
# - USB device not mounted (verify generic-device-plugin)
# - Incorrect device path in config
```

### Home Assistant Won't Start
```bash
# Check logs
kubectl --context homeops logs -n home-automation -l app.kubernetes.io/name=home-assistant

# Common issues:
# - Config validation errors (check configuration.yaml)
# - Missing secrets (verify sealed secrets created)
# - Cannot reach integrations (MQTT, ZWave)

# Check config validation
kubectl --context homeops exec -it -n home-automation <ha-pod> -- hass --script check_config
```

### Ingress Not Working
```bash
# Verify Traefik IngressRoute
kubectl --context homeops get ingressroute -n default home.dels.info -o yaml

# Verify ExternalName service points to HA
kubectl --context homeops get svc -n default home-dels-info -o yaml

# Check Traefik logs
kubectl --context homeops logs -n kube-system -l app.kubernetes.io/name=traefik

# Verify Cloudflare tunnel
kubectl --context homeops logs -n cloudflared -l app=cloudflared

# DNS check
dig home.dels.info
```

## Rollback Plan

If migration fails, services can be restored to previous state:

**Option 1: Delete ArgoCD applications** (keeps data)
```bash
kubectl --context homeops delete application -n argocd home-assistant zwavejs2mqtt ring-mqtt mosquitto
```

**Option 2: Delete namespace** (removes everything)
```bash
kubectl --context homeops delete namespace home-automation
```

**Option 3: Redeploy old server**
- Backups are intact at `/Volumes/Backup/dockerbian/`
- Docker compose files preserved
- Can restore to new/old hardware

## Post-Migration Cleanup

### Old Server
- Safely decommission after 1 week of stable operation
- Verify no services still referencing old IP (192.168.1.6)
- Update any hardcoded IPs in automations

### DNS
- Update internal DNS if using `.home.mc` or similar
- Verify `ha.delisle.me` resolves correctly
- Update any bookmarks/links

### Monitoring
- Add Home Assistant to your monitoring dashboard
- Configure Prometheus metrics (already exposed on HA)
- Add alerts for pod failures

### Backups
- Set up automated PVC backups via your NFS backup solution
- Consider GitOps for HA config (already using Git)
- Regular sealed secret backups

## Additional Notes

### Service URLs (Internal)
- Mosquitto: `mosquitto.home-automation.svc.cluster.local:1883` (MQTT)
- Mosquitto WebSocket: `mosquitto.home-automation.svc.cluster.local:9001`
- ZWaveJS2MQTT: `zwavejs2mqtt.home-automation.svc.cluster.local:3000` (WebSocket)
- ZWaveJS UI: `zwavejs2mqtt.home-automation.svc.cluster.local:8091` (HTTP)
- Ring-MQTT: `ring-mqtt.home-automation.svc.cluster.local:55123` (HTTP)
- Home Assistant: `home-assistant.home-automation.svc.cluster.local:8123` (HTTP)

### Resource Requests/Limits
- Mosquitto: 50m CPU, 64Mi RAM (limit: 200m, 256Mi)
- ZWaveJS2MQTT: 100m CPU, 128Mi RAM (limit: 500m, 512Mi)
- Ring-MQTT: 50m CPU, 128Mi RAM (limit: 300m, 512Mi)
- Home Assistant: 500m CPU, 512Mi RAM (limit: 2000m, 2Gi)

### USB Device Allocation
- Both ZWaveJS and HA request `squat.ai/serial: 1`
- generic-device-plugin provides `squat.ai/serial: 2` on minipc
- Sufficient capacity for both services

### ArgoCD Sync Waves
Order of deployment:
1. Wave 0: Mosquitto (foundational service)
2. Wave 1: ZWaveJS2MQTT, Ring-MQTT (depend on Mosquitto)
3. Wave 2: Home Assistant (depends on all services)

This ensures proper startup order and prevents race conditions.

---

**Questions or issues?** Check logs and pod status first. Most issues are configuration-related (secrets, USB paths, service URLs).
