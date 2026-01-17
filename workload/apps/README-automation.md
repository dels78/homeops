# Automation Stack Deployment

This document describes the deployment of the automation stack consisting of:
- **PostgreSQL**: Shared database for n8n and ClawdBot
- **n8n**: Workflow orchestration and automation platform
- **ClawdBot**: Multi-channel AI assistant interface

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    User Interactions                         │
│  (WhatsApp, Telegram, Slack, Discord, Signal, iMessage)     │
└──────────────────────────┬──────────────────────────────────┘
                           │
                    ┌──────▼──────┐
                    │  ClawdBot   │
                    │  (Node.js)  │
                    └──────┬──────┘
              ┌────────────┼────────────┐
              │            │            │
      ┌───────▼──────┐ ┌──▼─────┐ ┌───▼──────────┐
      │     n8n      │ │ Focus  │ │ External     │
      │ Workflows    │ │   AI   │ │ Services     │
      └──────┬───────┘ └───┬────┘ └──────────────┘
             │             │
      ┌──────▼─────────────▼──────┐
      │  PostgreSQL Database      │
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
CLAWDBOT_PASSWORD=$(openssl rand -base64 32)

# Create sealed secret
kubectl create secret generic postgresql-credentials \
  --from-literal=postgres-password="$POSTGRES_PASSWORD" \
  --from-literal=n8n-password="$N8N_PASSWORD" \
  --from-literal=clawdbot-password="$CLAWDBOT_PASSWORD" \
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
# Get your API keys
ANTHROPIC_API_KEY="your-anthropic-api-key"  # Get from https://console.anthropic.com
# Optional: OPENAI_API_KEY, TELEGRAM_TOKEN, DISCORD_TOKEN, etc.

# Create sealed secret (use same CLAWDBOT_PASSWORD from above)
kubectl create secret generic clawdbot-secrets \
  --from-literal=anthropic-api-key="$ANTHROPIC_API_KEY" \
  --from-literal=openai-api-key="" \
  --from-literal=db-password="$CLAWDBOT_PASSWORD" \
  --from-literal=whatsapp-token="" \
  --from-literal=telegram-token="" \
  --from-literal=discord-token="" \
  --from-literal=slack-token="" \
  --namespace=automation \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > workload/apps/clawdbot/manifests/sealedsecret-credentials.yaml

# Uncomment in kustomization.yaml
# Edit: workload/apps/clawdbot/kustomization.yaml
# Uncomment: - manifests/sealedsecret-credentials.yaml
```

### 4. Build ClawdBot Container Image

ClawdBot doesn't have an official pre-built image, so you need to build one:

```bash
# Clone ClawdBot repository
git clone https://github.com/bra1nDump/clawd-bot.git
cd clawd-bot

# Create Dockerfile if not present
cat > Dockerfile <<'EOF'
FROM node:20-alpine

WORKDIR /app

# Install dependencies
COPY package*.json ./
RUN npm ci --only=production

# Copy application code
COPY . .

# Expose port (adjust based on ClawdBot config)
EXPOSE 3000

# Health check endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# Start ClawdBot
CMD ["npm", "start"]
EOF

# Build and push image
docker build -t ghcr.io/yourusername/clawdbot:latest .
docker push ghcr.io/yourusername/clawdbot:latest

# Update kustomization.yaml with actual image
# Edit: workload/apps/clawdbot/kustomization.yaml
# Update image name and tag
```

**Note:** You may need to adjust the Dockerfile based on ClawdBot's actual structure and requirements. Check the official repository for build instructions.

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
