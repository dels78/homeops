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

## GitHub App auth (recommended)

Home Assistant can optionally push config changes back to `dels78/home-assistant` and trigger workflows without using a long-lived PAT by using a GitHub App installation token.

- **Home Assistant repo** expects:
  - `github_app_id` and `github_app_installation_id` in `/config/secrets.yaml`
  - the private key PEM mounted at `/config/github_app_private_key.pem`

### Create the sealed secret

1. Create a local PEM file (do **not** commit it), e.g. `~/Downloads/github-app-private-key.pem`.
2. Create the secret YAML and seal it (controller name/namespace may differ in your cluster):

```bash
kubectl --context homeops -n home-automation create secret generic home-assistant-github-app \
  --from-file=github_app_private_key.pem=~/Downloads/github-app-private-key.pem \
  --dry-run=client -o yaml \
| kubeseal --context homeops --format yaml \
  --controller-name sealed-secrets-controller \
  --controller-namespace sealed-secrets \
> workload/apps/home-assistant/manifests/sealedsecret-github-app.yaml
```

3. Uncomment `manifests/sealedsecret-github-app.yaml` in `workload/apps/home-assistant/kustomization.yaml`.

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
