# ClawdBot Deployment

## Initial Setup / After Clearing Browser Cache

The ClawdBot Control UI requires authentication via a gateway token. After clearing browser cache or on first access, you need to provide the token via URL parameter.

### Access URL

```
https://clawdbot.delisle.me/?token=<GATEWAY_TOKEN>
```

To get the current gateway token:

```bash
kubectl get secret clawdbot-secrets -n automation -o jsonpath='{.data.gateway-token}' | base64 -d && echo
```

Or construct the full URL:

```bash
TOKEN=$(kubectl get secret clawdbot-secrets -n automation -o jsonpath='{.data.gateway-token}' | base64 -d)
echo "https://clawdbot.delisle.me/?token=$TOKEN"
```

### What Happens

1. The UI reads the token from the `?token=` URL parameter
2. Stores it in browser localStorage (key: `clawdbot.control.settings.v1`)
3. Strips the token from the URL for security
4. Future visits to https://clawdbot.delisle.me/ work without the token parameter

### Why This Process

ClawdBot is designed for local CLI usage where `clawdbot dashboard` generates this URL automatically. In our Kubernetes deployment, we need to construct it manually.

## Architecture

- **Image**: Built from https://github.com/clawdbot/clawdbot
- **Platform**: linux/amd64 (built with `--platform` flag)
- **Storage**: NFS-backed PVC at `/home/node` (contains `.clawdbot` config and `clawd` workspace)
- **Bootstrap**: initContainer copies minimal config from ConfigMap if not exists
- **Config**: User configuration via Control UI persists to PVC

## Troubleshooting

### Control UI Shows "Unauthorized"

Clear browser cache/localStorage and re-authenticate using the token URL above.

### Check Pod Status

```bash
kubectl get pods -n automation -l app.kubernetes.io/name=clawdbot
kubectl logs -n automation -l app.kubernetes.io/name=clawdbot --tail=50
```

### Check Gateway Token

```bash
# In secret
kubectl get secret clawdbot-secrets -n automation -o jsonpath='{.data.gateway-token}' | base64 -d && echo

# In running config
kubectl exec -n automation deploy/clawdbot -- cat /home/node/.clawdbot/clawdbot.json | grep -A 3 '"auth"'
```
