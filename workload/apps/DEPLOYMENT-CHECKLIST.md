# Automation Stack Deployment Checklist

This checklist covers the manual steps needed to complete the n8n and ClawdBot deployment after merging PR.

## Prerequisites

- [x] NFS storage prepared on 192.168.1.252 (`/volume1/postgresql` and `/volume1/n8n`)
- [x] Feature branch created with all manifests
- [ ] On home network (cluster accessible at 192.168.1.191:6443)
- [ ] GitHub Personal Access Token with `write:packages` scope

## Step 1: Build and Push ClawdBot Image

The ClawdBot image build succeeded locally but push failed due to insufficient permissions on the `gh` CLI token.

### Create GitHub PAT

1. Go to https://github.com/settings/tokens/new
2. Create a token with these scopes:
   - `write:packages` (required for pushing to ghcr.io)
   - `read:packages` (required for pulling)
3. Save the token securely

### Build and Push Image

```bash
cd workload/apps/clawdbot

# Authenticate to ghcr.io with your PAT
export GITHUB_TOKEN="<YOUR_PAT_HERE>"
echo "${GITHUB_TOKEN}" | docker login ghcr.io -u dels78 --password-stdin

# Build and push (script already fixed with patches workaround)
./build-image.sh

# Verify image exists
docker pull ghcr.io/dels78/clawdbot:v2026.1.16-2
```

**Expected output:**
```
✓ Successfully built and pushed:
  ghcr.io/dels78/clawdbot:v2026.1.16-2
  ghcr.io/dels78/clawdbot:latest
```

## Step 2: Create Sealed Secrets

**Important:** Must be on home network with cluster access.

### Switch to homeops kubectl context

```bash
kubectl config use-context homeops

# Verify cluster access
kubectl get nodes
```

### Create PostgreSQL Sealed Secret

```bash
cd /path/to/homeops

# Generate random passwords
POSTGRES_PASSWORD=$(openssl rand -base64 32)
N8N_PASSWORD=$(openssl rand -base64 32)

# Save passwords securely (optional but recommended)
echo "POSTGRES_PASSWORD=${POSTGRES_PASSWORD}" >> ~/.homeops-secrets.env
echo "N8N_PASSWORD=${N8N_PASSWORD}" >> ~/.homeops-secrets.env
chmod 600 ~/.homeops-secrets.env

# Create sealed secret
kubectl create secret generic postgresql-credentials \
  --from-literal=postgres-password="$POSTGRES_PASSWORD" \
  --from-literal=n8n-password="$N8N_PASSWORD" \
  --namespace=automation \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > workload/system/postgresql/manifests/sealedsecret-credentials.yaml

# Verify file was created
ls -lh workload/system/postgresql/manifests/sealedsecret-credentials.yaml
```

### Create n8n Sealed Secret

```bash
# Generate encryption key
N8N_ENCRYPTION_KEY=$(openssl rand -base64 32)

# Save encryption key securely
echo "N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}" >> ~/.homeops-secrets.env

# Create sealed secret (reuse N8N_PASSWORD from above)
kubectl create secret generic n8n-secrets \
  --from-literal=encryption-key="$N8N_ENCRYPTION_KEY" \
  --from-literal=db-password="$N8N_PASSWORD" \
  --namespace=automation \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > workload/apps/n8n/manifests/sealedsecret-encryption.yaml

# Verify file was created
ls -lh workload/apps/n8n/manifests/sealedsecret-encryption.yaml
```

### Create ClawdBot Sealed Secret

```bash
# Get Claude AI session key
# 1. Go to https://claude.ai and log in with your personal account
# 2. Open browser DevTools (F12)
# 3. Go to Application/Storage > Cookies
# 4. Find the sessionKey cookie value
# See: https://docs.clawd.bot for detailed instructions

CLAUDE_SESSION_KEY="<YOUR_CLAUDE_SESSION_KEY>"
GATEWAY_TOKEN=$(openssl rand -base64 32)

# Save tokens securely
echo "CLAUDE_SESSION_KEY=${CLAUDE_SESSION_KEY}" >> ~/.homeops-secrets.env
echo "CLAWDBOT_GATEWAY_TOKEN=${GATEWAY_TOKEN}" >> ~/.homeops-secrets.env

# Create sealed secret
kubectl create secret generic clawdbot-secrets \
  --from-literal=claude-session-key="$CLAUDE_SESSION_KEY" \
  --from-literal=gateway-token="$GATEWAY_TOKEN" \
  --namespace=automation \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > workload/apps/clawdbot/manifests/sealedsecret-credentials.yaml

# Verify file was created
ls -lh workload/apps/clawdbot/manifests/sealedsecret-credentials.yaml
```

## Step 3: Uncomment Sealed Secrets in Kustomization Files

Edit the following files and uncomment the sealed secret lines:

### workload/system/postgresql/kustomization.yaml
```bash
# Change this:
  # - manifests/sealedsecret-credentials.yaml

# To this:
  - manifests/sealedsecret-credentials.yaml
```

### workload/apps/n8n/kustomization.yaml
```bash
# Change this:
  # - manifests/sealedsecret-encryption.yaml

# To this:
  - manifests/sealedsecret-encryption.yaml
```

### workload/apps/clawdbot/kustomization.yaml
```bash
# Change this:
  # - manifests/sealedsecret-credentials.yaml

# To this:
  - manifests/sealedsecret-credentials.yaml
```

## Step 4: Commit and Push Sealed Secrets

```bash
# Stage sealed secrets and kustomization changes
git add workload/system/postgresql/manifests/sealedsecret-credentials.yaml
git add workload/system/postgresql/kustomization.yaml
git add workload/apps/n8n/manifests/sealedsecret-encryption.yaml
git add workload/apps/n8n/kustomization.yaml
git add workload/apps/clawdbot/manifests/sealedsecret-credentials.yaml
git add workload/apps/clawdbot/kustomization.yaml
git add workload/apps/clawdbot/build-image.sh

# Check what's being committed
git status

# Commit
git commit -m "Add sealed secrets for automation stack

Created sealed secrets for:
- PostgreSQL credentials (postgres + n8n users)
- n8n encryption key and database password
- ClawdBot Claude AI session key and gateway token

Also updated build-image.sh with patches directory workaround.

Co-Authored-By: Claude <noreply@anthropic.com>"

# Push to feature branch
git push origin feature/add-n8n-clawdbot
```

## Step 5: Merge PR and Monitor Deployment

```bash
# Merge the PR on GitHub
# ArgoCD will automatically sync the applications

# Monitor ArgoCD applications
kubectl get applications -n argocd | grep -E "postgresql|n8n|clawdbot"

# Watch pod creation
kubectl get pods -n automation -w

# Check specific application status
argocd app get postgresql
argocd app get n8n
argocd app get clawdbot

# View logs if needed
kubectl logs -n automation -l app.kubernetes.io/name=postgresql
kubectl logs -n automation -l app.kubernetes.io/name=n8n
kubectl logs -n automation -l app.kubernetes.io/name=clawdbot
```

## Step 6: Post-Deployment Verification

### Verify PostgreSQL

```bash
# Check pod is running
kubectl get pod -n automation postgresql-0

# Verify databases exist
kubectl exec -n automation postgresql-0 -- psql -U postgres -c '\l'
# Should show: postgres, n8n databases

# Test connection
kubectl exec -n automation postgresql-0 -- psql -U n8n -d n8n -c 'SELECT version();'
```

### Access n8n

1. Navigate to https://n8n.delisle.me
2. Create admin account
3. Verify database connection is working
4. Configure OAuth connections for external services (GitHub, Slack, Gmail, etc.)

### Access ClawdBot

1. Navigate to https://clawdbot.delisle.me
2. Verify gateway is accessible
3. Configure messaging platform integrations (Telegram, Discord, etc.)
4. Test connection with a simple command

## Troubleshooting

### ClawdBot image not found

```bash
# Verify image exists in registry
docker pull ghcr.io/dels78/clawdbot:v2026.1.16-2

# If not, rebuild and push
cd workload/apps/clawdbot
./build-image.sh
```

### Sealed secrets not working

```bash
# Check sealed-secrets controller is running
kubectl get pods -n kube-system | grep sealed-secrets

# Check secret was created
kubectl get secret -n automation postgresql-credentials
kubectl get secret -n automation n8n-secrets
kubectl get secret -n automation clawdbot-secrets

# View secret (base64 encoded)
kubectl get secret -n automation postgresql-credentials -o yaml
```

### PostgreSQL won't start

```bash
# Check NFS mount
kubectl describe pod -n automation postgresql-0 | grep -A10 "Volumes:"

# Verify NFS path exists on server
ssh admin@192.168.1.252 ls -la /volume1/postgresql

# Check init script logs
kubectl logs -n automation postgresql-0
```

### n8n can't connect to database

```bash
# Check PostgreSQL is running
kubectl get pod -n automation postgresql-0

# Verify database exists
kubectl exec -n automation postgresql-0 -- psql -U postgres -c '\l'

# Check n8n secret has correct password
kubectl get secret -n automation n8n-secrets -o jsonpath='{.data.db-password}' | base64 -d

# Compare with PostgreSQL secret
kubectl get secret -n automation postgresql-credentials -o jsonpath='{.data.n8n-password}' | base64 -d
```

### Cluster unreachable

```bash
# Ensure you're on home network
ping 192.168.1.191

# Switch to correct context
kubectl config use-context homeops

# Verify cluster access
kubectl get nodes
```

## Security Notes

- **Never commit unsealed secrets** to git
- Store generated passwords in secure password manager
- Rotate Claude AI session key if compromised
- ClawdBot image is built from public ClawdBot repository (verify source before building)
- Sealed secrets can only be decrypted by the cluster's sealed-secrets controller

## Reference

- Full documentation: `workload/apps/README-automation.md`
- ClawdBot GitHub: https://github.com/clawdbot/clawdbot
- n8n Documentation: https://docs.n8n.io
- Sealed Secrets: https://github.com/bitnami-labs/sealed-secrets
