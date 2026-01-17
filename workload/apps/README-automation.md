# Automation Stack Deployment

This document describes the deployment of the automation stack consisting of:
- **PostgreSQL**: Database for n8n (for workflow state and execution history)
- **n8n**: Workflow orchestration and automation platform
- **ClawdBot**: Multi-channel AI assistant interface (uses filesystem storage)

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    User Interactions                         │
│  (WhatsApp, Telegram, Slack, Discord, Signal, iMessage)     │
└──────────────────────────┬──────────────────────────────────┘
                           │
                    ┌──────▼──────┐
                    │  ClawdBot   │ ← NFS PVC (clawdbot-data)
                    │  (Node.js)  │   (config + workspace)
                    └──────┬──────┘
              ┌────────────┼────────────┐
              │            │            │
      ┌───────▼──────┐ ┌──▼─────┐ ┌───▼──────────┐
      │     n8n      │ │ Focus  │ │ External     │
      │ Workflows    │ │   AI   │ │ Services     │
      └──────┬───────┘ └───┬────┘ └──────────────┘
             │             │
      ┌──────▼─────────────▼──────┐
      │  PostgreSQL Database      │ ← NFS: /volume1/postgresql
      │  (n8n workflows/state)    │   NFS: /volume1/n8n (n8n data)
      └───────────────────────────┘
```

## Deployment Steps

### 1. Prerequisites

Ensure the following are already deployed in your cluster:
- ArgoCD
- Sealed Secrets controller
- NFS client provisioner (storageClass: `nfs-client`)
- Traefik ingress controller
- Cloudflare Zero Trust configured for `*.delisle.me`

### 2. Prepare NFS Storage

On your NFS server (192.168.1.252), create the following directories:

```bash
# On NFS server
mkdir -p /volume1/postgresql
mkdir -p /volume1/n8n
chown -R 1000:1000 /volume1/postgresql /volume1/n8n
chmod 750 /volume1/postgresql /volume1/n8n
```

### 3. Create Sealed Secrets

#### PostgreSQL Credentials

```bash
# Generate random passwords
POSTGRES_PASSWORD=$(openssl rand -base64 32)
N8N_PASSWORD=$(openssl rand -base64 32)

# Create sealed secret
kubectl create secret generic postgresql-credentials \
  --from-literal=postgres-password="$POSTGRES_PASSWORD" \
  --from-literal=n8n-password="$N8N_PASSWORD" \
  --namespace=automation \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > workload/system/postgresql/manifests/sealedsecret-credentials.yaml

# Uncomment in kustomization.yaml
# Edit: workload/system/postgresql/kustomization.yaml
# Uncomment: - manifests/sealedsecret-credentials.yaml
```

#### n8n Secrets

```bash
# Generate encryption key
N8N_ENCRYPTION_KEY=$(openssl rand -base64 32)

# Create sealed secret (use same N8N_PASSWORD from above)
kubectl create secret generic n8n-secrets \
  --from-literal=encryption-key="$N8N_ENCRYPTION_KEY" \
  --from-literal=db-password="$N8N_PASSWORD" \
  --namespace=automation \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > workload/apps/n8n/manifests/sealedsecret-encryption.yaml

# Uncomment in kustomization.yaml
# Edit: workload/apps/n8n/kustomization.yaml
# Uncomment: - manifests/sealedsecret-encryption.yaml
```

#### ClawdBot Secrets

```bash
# Get Claude AI session key
# 1. Go to https://claude.ai and log in
# 2. Open browser DevTools (F12)
# 3. Go to Application/Storage > Cookies
# 4. Find the sessionKey cookie value
# See: https://docs.clawd.bot for detailed instructions

CLAUDE_SESSION_KEY="your-claude-session-key"
GATEWAY_TOKEN=$(openssl rand -base64 32)

# Create sealed secret
kubectl create secret generic clawdbot-secrets \
  --from-literal=claude-session-key="$CLAUDE_SESSION_KEY" \
  --from-literal=gateway-token="$GATEWAY_TOKEN" \
  --namespace=automation \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > workload/apps/clawdbot/manifests/sealedsecret-credentials.yaml

# Uncomment in kustomization.yaml
# Edit: workload/apps/clawdbot/kustomization.yaml
# Uncomment: - manifests/sealedsecret-credentials.yaml
```

### 4. Build ClawdBot Container Image

**Important:** ClawdBot doesn't publish official pre-built images yet (as of January 2026). You must build the image yourself from their GitHub releases.

#### Option A: Use the Build Script (Recommended)

```bash
cd workload/apps/clawdbot

# Make script executable
chmod +x build-image.sh

# Build image for the version specified in kustomization.yaml
./build-image.sh

# Or build a specific version
./build-image.sh v2026.1.16-2
```

#### Option B: Manual Build

```bash
# Set version (check latest at https://github.com/clawdbot/clawdbot/releases)
VERSION="v2026.1.16-2"

# Clone ClawdBot repository
git clone --branch ${VERSION} --depth 1 https://github.com/clawdbot/clawdbot.git
cd clawdbot

# Build using their Dockerfile
docker build -t ghcr.io/dels78/clawdbot:${VERSION} -t ghcr.io/dels78/clawdbot:latest .

# Push to registry (requires authentication to ghcr.io)
docker push ghcr.io/dels78/clawdbot:${VERSION}
docker push ghcr.io/dels78/clawdbot:latest
```

#### Renovate Integration

The ClawdBot kustomization.yaml is configured to track GitHub releases:

```yaml
images:
  - name: ghcr.io/dels78/clawdbot
    # renovate: datasource=github-releases depName=clawdbot/clawdbot
    newTag: "v2026.1.16-2"
```

When renovate detects a new ClawdBot release, it will create a PR updating the tag. You'll need to:
1. Rebuild the image with the new version
2. Push to your registry
3. Merge the renovate PR

**Future:** Once ClawdBot publishes official images to Docker Hub or GHCR, update the image reference and renovate will track those automatically.

### 5. Deploy via ArgoCD

Once secrets are created and the ClawdBot image is built:

```bash
# Commit your changes
git add .
git commit -m "Add n8n and ClawdBot automation stack"
git push origin feature/add-n8n-clawdbot

# Create pull request and merge to main
# ArgoCD will automatically detect and deploy the applications

# Monitor deployment
kubectl get applications -n argocd
argocd app get postgresql
argocd app get n8n
argocd app get clawdbot

# Check pod status
kubectl get pods -n automation
```

### 6. Access Services

Once deployed, access the services:

- **n8n**: https://n8n.delisle.me
- **ClawdBot webhooks**: https://clawdbot.delisle.me
- **PostgreSQL**: `postgresql.automation.svc.cluster.local:5432` (internal only)

Both n8n and ClawdBot are protected by Cloudflare Zero Trust.

### 7. Initial Configuration

#### n8n Setup

1. Access https://n8n.delisle.me
2. Create admin account
3. Configure OAuth connections for external services (GitHub, Slack, Gmail, etc.)
4. Import initial workflows for Focus AI integration

#### ClawdBot Setup

1. Configure messaging platform integrations (Telegram, Discord, etc.)
2. Set up webhook URLs pointing to `https://clawdbot.delisle.me/webhooks/<platform>`
3. Test connection with a simple message
4. Configure ClawdBot to call n8n workflows

## Service Dependencies

The applications are deployed with ArgoCD sync waves to ensure proper ordering:

1. **Wave 1**: PostgreSQL (database must be ready first)
2. **Wave 2**: n8n (depends on PostgreSQL)
3. **Wave 3**: ClawdBot (depends on PostgreSQL and optionally n8n)

## Troubleshooting

### PostgreSQL won't start

```bash
# Check NFS mount
kubectl describe pod -n automation postgresql-0
# Verify NFS path exists on server
ssh admin@192.168.1.252 ls -la /volume1/postgresql

# Check secrets
kubectl get secret -n automation postgresql-credentials
```

### n8n database connection fails

```bash
# Verify PostgreSQL is running
kubectl get pods -n automation
kubectl logs -n automation postgresql-0

# Check database was created
kubectl exec -n automation postgresql-0 -- psql -U postgres -c '\l'

# Verify n8n secret has correct password
kubectl get secret -n automation n8n-secrets -o jsonpath='{.data.db-password}' | base64 -d
```

### ClawdBot image pull fails

```bash
# Verify image exists
docker pull ghcr.io/yourusername/clawdbot:latest

# Check image pull secrets if using private registry
kubectl get secrets -n automation
```

## Cloudflare Service Tokens

For external services (GitHub webhooks, etc.) to reach n8n:

1. Go to Cloudflare Zero Trust > Access > Service Auth
2. Create a new service token
3. Configure n8n webhooks to include the token in headers
4. Add Cloudflare Access policy allowing service token

## Next Steps

1. **Configure n8n workflows** to replace Focus AI worker service
2. **Set up ClawdBot integrations** for messaging platforms
3. **Create initial workflows** for event ingestion from external services
4. **Test end-to-end flow**: External event → n8n → Database → ClawdBot query
5. **Deploy Focus AI services** (agent, API, MCP) to Kubernetes

## Related Documentation

- Focus AI Architecture: `/Users/martindelisle/code/personal/focus-ai/README.md`
- n8n Documentation: https://docs.n8n.io
- ClawdBot GitHub: https://github.com/bra1nDump/clawd-bot
- ArgoCD: https://argo-cd.readthedocs.io
