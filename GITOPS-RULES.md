# GitOps & ArgoCD Development Rules

## Critical: Test Before Committing

**ALWAYS test kustomize builds locally before committing changes to ArgoCD Applications or Kustomize configurations.**

### For Standard Kustomize
```bash
kustomize build <path>
```

### For Kustomize with Helm Charts
```bash
kustomize build <path> --enable-helm
```

Verify:
- Output is valid YAML
- No error messages
- All expected resources are present
- No duplicate resource IDs

## Preserve Existing Configuration

When modifying ArgoCD Applications:

1. **Read the original file completely** before making changes
2. **Preserve all existing fields**:
   - `plugin.name` - CRITICAL for Helm chart processing (argocd-lovely-plugin)
   - `finalizers` - Required for proper resource cleanup
   - `annotations` - Slack notifications, sync waves, etc.
3. **If unsure what a field does, ask before removing it**
4. **Document why you're changing any field**

## When Errors Occur

**STOP and investigate - do not create multiple conflicting PRs**

1. Check ArgoCD application status:
   ```bash
   kubectl get application <name> -n argocd -o yaml
   kubectl get application <name> -n argocd -o jsonpath='{.status.conditions}' | jq
   ```

2. Read the complete error message
3. Identify the root cause
4. Propose ONE fix with clear explanation
5. Wait for user confirmation before proceeding

## Never Panic-Revert

If a change causes an outage:

1. **Analyze the root cause first**
2. **Propose a single targeted fix** - don't create:
   - Multiple competing PRs
   - Hotfix branches that revert reverts
   - Rushed changes without understanding the problem
3. **Ask which approach the user prefers** if multiple options exist
4. **One PR, one fix, done right**

## Production GitOps is Live

- Merged PRs deploy immediately via ArgoCD auto-sync
- Deleted ArgoCD Applications = deleted Kubernetes resources = deleted pods
- **There is no undo button** - get it right the first time
- Test the change, understand the impact, then commit

## Common Pitfalls

### 1. Missing argocd-lovely-plugin
If your kustomization uses `helmCharts`, the ArgoCD Application MUST have:
```yaml
source:
  plugin:
    name: argocd-lovely-plugin
```

### 2. Duplicate Resources
When creating parent kustomizations that reference child kustomizations:
- Each resource (Namespace, ConfigMap, etc.) can only be defined once
- If children define a resource, parent must not
- Or create the resource once in parent and remove from children

### 3. Namespace Management
ArgoCD Applications have `syncOptions: - CreateNamespace=true` which creates the namespace automatically. You typically don't need `namespace.yaml` in your kustomization unless you need specific labels/annotations.

## ArgoCD Application Template

When creating new ArgoCD Applications, use this template:

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  namespace: argocd
  name: <app-name>
  annotations:
    notifications.argoproj.io/subscribe.on-sync-failed.slack: argo
    notifications.argoproj.io/subscribe.on-sync-status-unknown.slack: argo
    notifications.argoproj.io/subscribe.on-health-degraded.slack: argo
    notifications.argoproj.io/subscribe.on-deployed.slack: argo
    argocd.argoproj.io/sync-wave: "<number>"  # For ordering
  finalizers:
    - resources-finalizer.argocd.argoproj.io

spec:
  project: default

  source:
    repoURL: https://github.com/dels78/homeops.git
    targetRevision: HEAD
    path: <path-to-kustomization>/
    plugin:  # Only if using helmCharts
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

## Before You Commit Checklist

- [ ] Read all files you're modifying completely
- [ ] Tested with `kustomize build` (if possible)
- [ ] Preserved all existing fields (especially `plugin`, `finalizers`, `annotations`)
- [ ] Understood what each change does
- [ ] No duplicate resource definitions
- [ ] Created only ONE PR for the fix
- [ ] Documented the change in commit message

## Remember

**GitOps mistakes are expensive**. A bad merge can take down services immediately. Take the time to understand, test, and get it right.

When in doubt, **ask first, commit second**.
