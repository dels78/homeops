# Home Assistant on K3S

Home automation stack running on homeops k3s cluster.

## Services

- **Mosquitto** - MQTT broker
- **ZWaveJS2MQTT** - Z-Wave device management with USB stick
- **Ring-MQTT** - Ring alarm sensors bridge  
- **Home Assistant** - Main automation hub with Zigbee/Matter USB dongle

## Quick Start

See [MIGRATION-HOME-ASSISTANT.md](../../docs/MIGRATION-HOME-ASSISTANT.md) for complete migration guide.

**TL;DR:**
```bash
# 1. Seal secrets
./scripts/seal-ha-secrets.sh

# 2. Commit and push (creates PR per Haus protocol)
git add .
git commit -m "feat: migrate Home Assistant to k3s"
git push origin feature/home-assistant-migration

# 3. Merge PR → ArgoCD auto-syncs

# 4. Monitor deployment
kubectl --context homeops get pods -n home-automation -w

# 5. Access HA
open https://home.dels.info
```

## Architecture

All services in `home-automation` namespace. USB devices on `minipc.dels.local` node.

**External access:** Home Assistant via `home.dels.info` (existing Traefik route)  
**Internal communication:** Services use k8s DNS (e.g., `mosquitto.home-automation.svc.cluster.local`)

## Troubleshooting

Check logs:
```bash
kubectl --context homeops logs -n home-automation -l app.kubernetes.io/name=<service-name>
```

Port-forward for debugging:
```bash
# ZWaveJS UI
kubectl --context homeops port-forward -n home-automation svc/zwavejs2mqtt 8091:8091

# Ring-MQTT UI
kubectl --context homeops port-forward -n home-automation svc/ring-mqtt 55123:55123
```

See full guide in [docs/MIGRATION-HOME-ASSISTANT.md](../../docs/MIGRATION-HOME-ASSISTANT.md).

