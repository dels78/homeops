# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GitOps-managed k3s home cluster running on Fedora CoreOS. All applications deploy via ArgoCD with automated sync enabled.

**Critical**: Merged PRs deploy immediately to production. There is no staging environment and no undo button. Test locally before committing.

## Core Principle: Default to Autonomous Execution

**When in doubt, ACT. Don't ask.**

You are expected to be autonomous. The user hired you to get work done, not to ask permission at every step.

### The "Just Fix It" Rule

If you're about to ask a question, first check:

- ❓ "Should I fix these validation errors?" → ❌ **DON'T ASK.** Just fix them.
- ❓ "Should I follow the pattern in other ArgoCD apps?" → ❌ **DON'T ASK.** Just follow it.
- ❓ "Should I add the required annotations?" → ❌ **DON'T ASK.** Yes, always add them.
- ❓ "Should I test kustomize build?" → ❌ **DON'T ASK.** Always test before committing.

### When "Just Fix It" Applies

✅ **Fixing errors**: YAML validation, kustomize build errors, pre-commit failures → just fix them
✅ **Following patterns**: ArgoCD annotations, labels, conventions → read existing apps, copy pattern
✅ **Documentation**: Changed manifests → update docs automatically
✅ **Reverting bad changes**: Made it worse → revert and try again

### The Only Valid Questions (Three Categories)

Ask the user ONLY in these cases:

1. **Architectural decisions with tradeoffs**
   - Example: "Should this be in apps/ or system/?" (organizational decision)
   - **First**: Check existing similar applications to infer the pattern
   - **Then**: If truly ambiguous, present recommendation

2. **Missing external information**
   - Credentials, sealed secrets, cluster-specific values
   - Example: "Need the NFS server IP for storage class"

3. **Production impact unclear**
   - Example: "This change will restart all pods - is this acceptable now?"
   - **First**: Attempt to infer from change context (if it's a bug fix, assume yes)
   - **Only if high-risk**: Ask with context

### Know Your Environment: Production Changes Are Immediate

Given that **every merge deploys to production immediately**:

✅ **Do validate thoroughly**:
- Always run `kustomize build` before committing
- Always run `pre-commit run --all-files`
- Test resource creation with `kubectl apply --dry-run=server`

✅ **Do follow patterns exactly**:
- Copy annotations from similar apps
- Match label conventions
- Use established storage classes, security contexts

❌ **Don't experiment**:
- Don't try new patterns without verifying they work elsewhere
- Don't skip validation steps
- Don't commit "I think this will work"

**Default to action. The user will tell you if you're doing something they don't want.**

## Development Commands

```bash
# Validate kustomization before committing
kustomize build workload/apps/<name>/
kustomize build workload/apps/<name>/ --enable-helm  # If using Helm charts

# Run pre-commit hooks
pre-commit run --all-files

# Create PR
./scripts/create-pr.sh
```

## Directory Structure

```
argocd/
├── applications/           # ArgoCD Application CRDs (one per app)
└── bootstrap/              # ArgoCD self-management

workload/
├── apps/                   # User-facing applications
│   ├── home-assistant/
│   ├── n8n/
│   ├── clawdbot/
│   ├── mosquitto/
│   └── ...
├── system/                 # Infrastructure components
│   ├── traefik-home/
│   ├── metallb/
│   ├── sealed-secrets/
│   ├── postgresql/
│   └── ...
├── monitoring/             # Observability stack
│   ├── loki/
│   ├── kube-prometheus-stack/
│   └── ...
└── automation-stack/       # Composite application (combines children)

infrastructure/
└── coreos/                 # Node provisioning (Butane → Ignition)

scripts/                    # Automation tools
```

## ArgoCD Application Pattern

Every application needs two things:

1. **ArgoCD Application** (`argocd/applications/<name>.yaml`):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  namespace: argocd
  name: <name>
  annotations:
    notifications.argoproj.io/subscribe.on-sync-failed.slack: argo
    notifications.argoproj.io/subscribe.on-sync-status-unknown.slack: argo
    notifications.argoproj.io/subscribe.on-health-degraded.slack: argo
    notifications.argoproj.io/subscribe.on-deployed.slack: argo
    argocd.argoproj.io/sync-wave: "1"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/dels78/homeops.git
    targetRevision: HEAD
    path: workload/{apps,system,monitoring}/<name>/
    plugin:  # ONLY if using Helm charts
      name: argocd-lovely-plugin
  destination:
    server: https://kubernetes.default.svc
    namespace: <namespace>
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

2. **Kustomization** (`workload/{apps,system,monitoring}/<name>/kustomization.yaml`):
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: <namespace>
resources:
  - manifests/namespace.yaml
  - manifests/deployment.yaml
  - manifests/service.yaml
labels:
  - pairs:
      app.kubernetes.io/name: <name>
      app.kubernetes.io/instance: <name>
images:
  - name: <image>
    newName: <image>
    # renovate: datasource=docker depName=<image>
    newTag: "1.2.3"
```

## Key Conventions

**ArgoCD Applications:**
- Always include finalizer `resources-finalizer.argocd.argoproj.io` (cascade delete)
- Use `plugin: {name: argocd-lovely-plugin}` if kustomization uses `helmCharts`
- Sync waves control deployment order (negative = early)
- All 4 Slack notification annotations required

**Kubernetes Resources:**
- Labels: `app.kubernetes.io/name` and `app.kubernetes.io/instance`
- Storage: `storageClassName: nfs-client`
- Security: `runAsUser: 1000, runAsGroup: 1000, fsGroup: 1000`
- Strategy: `type: Recreate` for single-replica stateful apps

**Renovate Comments:**
```yaml
# renovate: datasource=docker depName=eclipse-mosquitto
newTag: "2.0.22"
```

## Adding a New Application

```bash
# 1. Create directory structure
mkdir -p workload/apps/myapp/manifests

# 2. Create manifests (namespace.yaml, deployment.yaml, service.yaml, etc.)

# 3. Create kustomization.yaml

# 4. Test build
kustomize build workload/apps/myapp/

# 5. Create ArgoCD Application
vim argocd/applications/myapp.yaml

# 6. Validate and commit
pre-commit run --all-files
git add . && git commit -m "feat: add myapp" && git push
```

## Sealed Secrets

For sensitive data, use sealed-secrets:

```bash
# Home Assistant secrets
./scripts/seal-ha-secrets.sh

# Generic secrets
kubectl create secret generic name --from-literal=key=value \
  --dry-run=client -o yaml | \
  kubeseal --controller-namespace sealed-secrets \
  --controller-name sealed-secrets -o yaml > manifests/sealedsecret-name.yaml
```

## Node Provisioning

New cluster nodes use Butane/Ignition for zero-touch setup:

```bash
cd infrastructure/coreos
cp .env.example .env
# Edit .env: K3S_TOKEN, K3S_SERVER

./build-ignition.sh <hostname>
# Boot Fedora CoreOS live ISO, then:
# sudo coreos-installer install /dev/sda --ignition-url http://<ip>:8080/<hostname>.ign
```

## Common Pitfalls

| Pitfall | Prevention |
|---------|-----------|
| Wrong GitHub account | Ensure the correct dotfiles profile is loaded |
| Broken kustomize | Test: `kustomize build <path>` before commit |
| Missing plugin | If using Helm, add `plugin: {name: argocd-lovely-plugin}` |
| Duplicate resources | Each resource defined once; organize parent/children carefully |
| Deleted app = deleted resources | Finalizers + auto-prune = immediate cleanup |
| Lost secrets | Never commit unencrypted; use sealed-secrets |

