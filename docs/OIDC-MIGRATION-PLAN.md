# OIDC Migration Plan - Temporal and Homeops Services

**Status**: Planning Phase
**Created**: January 20, 2026
**Author**: Martin + Claude
**Priority**: Medium (when time permits)

## Executive Summary

This document outlines the plan to implement proper OIDC authentication for Temporal Web UI and potentially other homeops services, following the pattern established in the Haus work environment (gitops-argocd).

**Current State**: Services rely solely on Cloudflare Access (GitHub OAuth) for authentication
**Target State**: Services use Dex as OIDC provider with Google Workspace, providing JWT-based authentication with future RBAC capabilities

---

## Table of Contents

1. [Background & Context](#background--context)
2. [Current Authentication Architecture](#current-authentication-architecture)
3. [Target Authentication Architecture](#target-authentication-architecture)
4. [Gateway API Considerations](#gateway-api-considerations)
5. [Implementation Plan](#implementation-plan)
6. [Secret Management Strategy](#secret-management-strategy)
7. [Service Migration Order](#service-migration-order)
8. [Testing Plan](#testing-plan)
9. [Rollback Strategy](#rollback-strategy)
10. [References](#references)

---

## Background & Context

### Problem Statement

Currently, Temporal Web UI and other services are accessible via Cloudflare Access which authenticates users via GitHub OAuth. However:

1. **No user identity at application level**: Applications don't know who the authenticated user is
2. **No RBAC**: Cannot implement role-based access control within applications
3. **No audit trail**: Cannot track which user performed which actions
4. **Inconsistent with work setup**: Personal homeops differs from Haus work environment

### What We Learned from Haus Setup

The Haus work environment (`/Users/martindelisle/code/Haus/gitops-argocd`) implements a robust OIDC setup:

**Architecture**:
```
User → Google Workspace OAuth → Dex (OIDC Provider) → Application
                                  ↓
                             JWT with email/groups
                                  ↓
                             RBAC policy mapping
```

**Key Components**:
- **Dex**: Acts as OIDC provider, bridges Google OAuth to applications
- **Google Workspace**: Identity provider
- **External Secrets Operator**: Fetches credentials from GCP Secret Manager
- **Gateway API**: Modern ingress (via GKE managed ingress)
- **RBAC Policies**: Map Google groups to application roles

**Files of Interest** (in Haus repo):
- `/code/Haus/gitops-argocd/clusters/haus-prod/dex/kustomization.yaml` - Dex config
- `/code/Haus/gitops-argocd/clusters/haus-prod/dex/manifests/dex-*-external-secret.yaml` - Secrets
- `/code/Haus/gitops-argocd/clusters/haus-prod/argo-workflows/kustomization.yaml` - SSO integration example
- `/code/Haus/gitops-argocd/components/core/argocd/patches/patch-argocd-rbac-cm.yaml` - RBAC policies

---

## Current Authentication Architecture

### Homeops (Personal)

```
┌─────────┐       ┌────────────────────┐       ┌─────────────┐
│  User   │──────▶│ Cloudflare Access  │──────▶│ Application │
└─────────┘       │  (GitHub OAuth)    │       │  (no auth)  │
                  └────────────────────┘       └─────────────┘
                           │
                           └─ Authenticates user
                           └─ Tunnels traffic
                           └─ NO JWT/headers passed
```

**Current Services**:
- **ArgoCD**: `argocd.delisle.me` - Behind CF Access, no OIDC
- **Temporal Web**: `temporal.delisle.me` - Behind CF Access, no auth at app level
- **n8n**: Internal only
- **Home Assistant**: `home.dels.info` - Behind CF Access

**Infrastructure**:
- **Ingress**: Traefik (k3s built-in)
- **Secrets**: Sealed Secrets + 1Password Connect Operator
- **DNS**: Cloudflare
- **Tunnel**: Cloudflare Tunnel (cloudflared)

### Current Temporal Configuration

**Files**:
- `workload/apps/temporal/values.yaml` - Helm chart values
- `workload/apps/temporal/manifests/worker.yaml` - Agent worker/webhook deployments
- `workload/apps/temporal/kustomization.yaml` - Kustomize config

**Temporal Web UI**:
- Ingress: Helm chart auto-generated
- Auth: None (unauthenticated UI)
- External access: Protected by Cloudflare Access only

**Current Namespaces**:
- `default` - Created manually via `tctl --namespace default namespace register --retention 7`

---

## Target Authentication Architecture

### Proposed Architecture

```
┌─────────┐       ┌──────────────────┐       ┌──────┐       ┌────────────────┐
│  User   │──────▶│ Google Workspace │──────▶│ Dex  │──────▶│ Temporal Web   │
└─────────┘       │   OAuth 2.0      │       │ OIDC │       │ UI (with auth) │
                  └──────────────────┘       └──────┘       └────────────────┘
                                               │
                                               ├─ JWT with email/groups
                                               ├─ Token validation
                                               └─ Future: RBAC mapping
```

**Flow**:
1. User navigates to `https://temporal.delisle.me`
2. Temporal Web UI redirects to Dex for authentication
3. Dex redirects to Google Workspace OAuth
4. User authenticates with Google account
5. Google redirects back to Dex with authorization code
6. Dex exchanges code for Google ID token
7. Dex issues its own JWT to Temporal
8. Temporal validates JWT and creates session
9. User identity (email) visible in Temporal UI

**Benefits**:
- ✅ User identity visible in Temporal UI
- ✅ Audit trail of who performed actions
- ✅ Foundation for future RBAC
- ✅ Consistent with Haus work environment
- ✅ Can extend to other services (ArgoCD, n8n, etc.)

### Why Google Workspace?

**Preferred Options** (in order):
1. **Google Workspace** ✅ (Recommended)
   - Mature OAuth provider
   - Already used at work (proven pattern)
   - Supports Google Groups for RBAC
   - Better developer experience

2. GitHub OAuth
   - Currently used by Cloudflare Access
   - Limited group/team support for personal accounts
   - Less mature OIDC implementation

3. Cloudflare Access as IdP
   - Simplest but least control
   - No RBAC within applications
   - Limited audit capabilities

---

## Gateway API Considerations

### Current Status (January 2026)

**k3s Gateway API Support**: ❌ Not native yet

Based on research ([k3s Issue #12183](https://github.com/k3s-io/k3s/issues/12183), [k3s Issue #11099](https://github.com/k3s-io/k3s/issues/11099)):
- k3s does **NOT** ship with Gateway API support out-of-the-box
- Traefik in k3s is missing Gateway API RBAC definitions
- Feature request open for Envoy Gateway integration ([k3s Issue #9351](https://github.com/k3s-io/k3s/issues/9351))
- Manual configuration possible but requires additional RBAC setup

### Options for Gateway API

**Option 1: Stay with Traefik + Standard Ingress** ⭐ (Recommended for now)
- **Pros**: Already working, stable, well-understood
- **Cons**: Less modern API, more verbose configuration
- **Effort**: Low - no changes needed

**Option 2: Manually Configure Traefik for Gateway API**
- **Pros**: Use Gateway API with existing Traefik
- **Cons**: Manual RBAC setup, certificate issues reported
- **Effort**: Medium - need to apply RBAC definitions and test
- **Reference**: [Traefik Community Forum](https://community.traefik.io/t/getting-started-with-kubernetes-gateway-api-and-traefik/23601/28)

**Option 3: Switch to Cilium CNI**
- **Pros**: Native Gateway API support, modern CNI with observability
- **Cons**: Complete CNI replacement, significant migration effort
- **Effort**: High - full cluster migration
- **Reference**: [Guide](https://blogs.learningdevops.com/the-complete-guide-to-setting-up-cilium-on-k3s-with-kubernetes-gateway-api-8f78adcddb4d)

**Option 4: Wait for k3s Native Support**
- **Pros**: Official support, maintained by k3s team
- **Cons**: Unknown timeline, may be months/years
- **Effort**: None - just wait

### Recommendation

**Stick with Traefik + Standard Ingress for now**. Gateway API migration can be a separate future project once k3s has better native support. Don't block OIDC implementation on Gateway API migration.

**Timeline**:
1. **Phase 1** (Now): Implement OIDC with current Traefik/Ingress
2. **Phase 2** (Future): Revisit Gateway API when k3s support matures

---

## Implementation Plan

### Phase 1: Dex Deployment (Foundation)

**Goal**: Deploy Dex as OIDC provider with Google Workspace connector

**Tasks**:
1. Create Google OAuth Client credentials
   - Go to Google Cloud Console
   - Create OAuth 2.0 Client ID for Dex
   - Redirect URI: `https://dex.delisle.me/callback`
   - Scopes: `openid`, `profile`, `email`, `groups` (optional)

2. Store credentials in 1Password
   - Item: "Dex Google OAuth Client"
   - Fields: `client_id`, `client_secret`
   - Vault: homeops-secrets (or appropriate vault)

3. Create 1Password Connect OnePasswordItem
   - File: `workload/system/dex/manifests/onepassworditem-google-oauth.yaml`
   - Reference credentials from 1Password vault

4. Create Dex Kustomize deployment
   - Directory: `workload/system/dex/`
   - Files:
     - `kustomization.yaml` - Main config
     - `manifests/deployment.yaml` - Dex pod
     - `manifests/service.yaml` - Dex service
     - `manifests/configmap.yaml` - Dex configuration
     - `manifests/onepassworditem-google-oauth.yaml` - OAuth credentials

5. Configure Dex
   - Issuer: `https://dex.delisle.me`
   - Google connector config
   - Static clients for Temporal (and future services)

6. Create Traefik IngressRoute for Dex
   - Host: `dex.delisle.me`
   - Backend: `dex:5556`
   - TLS via Cloudflare

7. Create ArgoCD Application for Dex
   - File: `argocd/applications/dex.yaml`
   - Auto-sync enabled

**Example Dex ConfigMap** (simplified):
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: dex-config
  namespace: dex
data:
  config.yaml: |
    issuer: https://dex.delisle.me
    storage:
      type: kubernetes
      config:
        inCluster: true
    web:
      http: 0.0.0.0:5556
    connectors:
      - type: google
        id: google
        name: Google
        config:
          issuer: https://accounts.google.com
          clientID: $GOOGLE_CLIENT_ID
          clientSecret: $GOOGLE_CLIENT_SECRET
          redirectURI: https://dex.delisle.me/callback
    staticClients:
      - id: temporal-web
        name: Temporal Web UI
        redirectURIs:
          - https://temporal.delisle.me/oauth2/callback
        secret: $TEMPORAL_CLIENT_SECRET
```

**Validation**:
- [ ] Dex pod running
- [ ] Can access `https://dex.delisle.me/.well-known/openid-configuration`
- [ ] OAuth flow works (test with curl/browser)

### Phase 2: Temporal OIDC Integration

**Goal**: Configure Temporal Web UI to use Dex for authentication

**Tasks**:
1. Generate Temporal OAuth client secret
   - Store in 1Password as `temporal-dex-client-secret`
   - Create OnePasswordItem to expose to Temporal namespace

2. Update Temporal Helm values
   - File: `workload/apps/temporal/values.yaml`
   - Add web OIDC configuration

3. Configure Temporal Web auth
   ```yaml
   web:
     enabled: true
     replicaCount: 1
     config:
       auth:
         enabled: true
         providers:
           - label: Google
             type: oidc
             issuer: https://dex.delisle.me
             client_id: temporal-web
             client_secret_env: TEMPORAL_WEB_CLIENT_SECRET
             scopes:
               - openid
               - profile
               - email
             callback_base_uri: https://temporal.delisle.me
     env:
       - name: TEMPORAL_WEB_CLIENT_SECRET
         valueFrom:
           secretKeyRef:
             name: temporal-dex-client
             key: client-secret
   ```

4. Create secret for Temporal
   - File: `workload/apps/temporal/manifests/onepassworditem-dex-client.yaml`

5. Update kustomization to include new secret

6. Deploy and test

**Validation**:
- [ ] Temporal Web UI shows login button
- [ ] Login redirects to Dex
- [ ] Dex redirects to Google
- [ ] After Google auth, redirected back to Temporal
- [ ] User email visible in Temporal UI

### Phase 3: Additional Services (Optional)

**Candidates**:
- ArgoCD (replace current unauthenticated setup)
- n8n (if we want to expose externally with auth)
- Future services

**Pattern**: Same as Temporal - create static client in Dex, configure service with OIDC

---

## Secret Management Strategy

### 1Password Connect Operator (Preferred)

**Current Setup**:
- 1Password Connect already deployed in cluster
- `OnePasswordItem` CRD available
- Used for GitHub App credentials in Temporal

**For Dex/OIDC**:
1. Create 1Password item with structure:
   ```
   Title: Dex Google OAuth Client
   Fields:
     - client_id: <google-oauth-client-id>
     - client_secret: <google-oauth-client-secret>

   Title: Temporal Dex Client
   Fields:
     - client-secret: <randomly-generated-secret>
   ```

2. Reference in OnePasswordItem:
   ```yaml
   apiVersion: onepassword.com/v1
   kind: OnePasswordItem
   metadata:
     name: dex-google-oauth
     namespace: dex
   spec:
     itemPath: "vaults/<vault-id>/items/<item-id>"
   ```

3. Mount as environment variables or volume in Dex pod

**Advantages over Sealed Secrets**:
- ✅ Secrets stored centrally in 1Password
- ✅ No encrypted blobs in git
- ✅ Easy rotation (update in 1Password)
- ✅ Better audit trail
- ✅ Native integration with existing workflow

---

## Service Migration Order

### Priority Order

1. **Temporal Web UI** (High Priority)
   - Currently unauthenticated at app level
   - Actively being used for workflow monitoring
   - Needs proper audit trail

2. **ArgoCD** (Medium Priority)
   - Currently relies only on CF Access
   - Would benefit from RBAC (future)
   - Less urgent as already somewhat protected

3. **n8n** (Low Priority)
   - Internal service
   - May not need external exposure
   - Can remain on current auth

4. **Home Assistant** (Not Applicable)
   - Already has built-in auth system
   - CF Access is sufficient
   - No need for OIDC integration

### Estimated Timeline

- **Phase 1 (Dex Deployment)**: 2-4 hours
  - Google OAuth setup: 30 min
  - 1Password items creation: 30 min
  - Dex manifests: 1-2 hours
  - Testing: 30-60 min

- **Phase 2 (Temporal Integration)**: 1-2 hours
  - Helm values update: 30 min
  - Secret creation: 15 min
  - Deployment & testing: 45-75 min

- **Phase 3 (Additional Services)**: 1-2 hours per service
  - Similar pattern to Temporal
  - Less discovery time needed

**Total**: 4-8 hours spread over multiple sessions

---

## Testing Plan

### Unit Testing (Per Service)

**Dex**:
```bash
# Test OIDC discovery endpoint
curl https://dex.delisle.me/.well-known/openid-configuration | jq

# Verify issuer
# Should return: {"issuer":"https://dex.delisle.me",...}

# Check Dex health
kubectl exec -n dex deployment/dex -- dex version
```

**Temporal**:
```bash
# Access Temporal Web UI
open https://temporal.delisle.me

# Should see:
# 1. Login button (not direct access)
# 2. Click login → redirects to Dex
# 3. Dex shows "Login with Google"
# 4. After Google auth → back to Temporal
# 5. User email visible in UI (top right)
```

### Integration Testing

**Full OAuth Flow**:
1. Clear browser cookies
2. Navigate to `https://temporal.delisle.me`
3. Click "Login"
4. Redirected to `https://dex.delisle.me/auth/google?...`
5. Redirected to Google OAuth consent screen
6. Approve (if first time) or auto-redirect
7. Back to Dex: `https://dex.delisle.me/callback?code=...`
8. Dex validates, issues JWT
9. Final redirect: `https://temporal.delisle.me/oauth2/callback?code=...`
10. Temporal validates JWT, creates session
11. User lands on Temporal UI dashboard
12. User email visible in top-right corner

**Negative Tests**:
- [ ] Direct access without auth redirects to login
- [ ] Invalid JWT rejected
- [ ] Expired JWT forces re-authentication
- [ ] Logout clears session and requires re-login

### Monitoring

**Post-Deployment Checks**:
```bash
# Check Dex logs
kubectl logs -n dex deployment/dex --tail=50

# Check Temporal Web logs
kubectl logs -n temporal deployment/temporal-web --tail=50

# Verify no auth errors
kubectl get events -n dex --sort-by='.lastTimestamp'
kubectl get events -n temporal --sort-by='.lastTimestamp'
```

---

## Rollback Strategy

### If Dex Deployment Fails

**Quick Rollback**:
```bash
# Delete Dex ArgoCD app (stops sync)
kubectl delete application -n argocd dex

# Delete Dex namespace
kubectl delete namespace dex

# Services remain accessible via Cloudflare Access
# No impact to existing functionality
```

### If Temporal OIDC Integration Fails

**Rollback Temporal Values**:
```bash
# Revert Temporal Helm values
git revert <commit-hash>
git push

# ArgoCD will auto-sync back to previous state
# Or manually sync:
kubectl patch application -n argocd temporal \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}' --type=merge
```

**Temporal remains accessible** - Cloudflare Access still protects the endpoint, just no app-level auth.

### Nuclear Option

**Complete Rollback**:
1. Delete all OIDC-related commits
2. Force-push to main
3. ArgoCD auto-syncs to clean state
4. Everything back to original CF Access-only setup

**Data Safety**: No risk to Temporal workflows or data - OIDC is purely authentication layer

---

## References

### Documentation

**Temporal OIDC**:
- [Temporal Web UI Configuration Reference](https://docs.temporal.io/references/web-ui-configuration)
- [Implementing Role-Based Authentication for Self-Hosted Temporal](https://www.bitovi.com/blog/implementing-role-based-authentication-for-self-hosted-temporal)
- [Temporal Community: SSO Configuration](https://community.temporal.io/t/how-to-configure-sso-for-temporal-in-helm-chart/2794)

**Dex**:
- [Dex Documentation](https://dexidp.io/docs/)
- [Dex Google Connector](https://dexidp.io/docs/connectors/google/)
- [Dex Kubernetes Storage](https://dexidp.io/docs/storage/#kubernetes-custom-resource-definitions-crds)

**k3s Gateway API**:
- [k3s Issue #12183 - Gateway API Support](https://github.com/k3s-io/k3s/issues/12183)
- [k3s Issue #11099 - Traefik Gateway API Clarification](https://github.com/k3s-io/k3s/issues/11099)
- [k3s Issue #9351 - Envoy Gateway Integration Request](https://github.com/k3s-io/k3s/issues/9351)
- [Cilium on k3s with Gateway API Guide](https://blogs.learningdevops.com/the-complete-guide-to-setting-up-cilium-on-k3s-with-kubernetes-gateway-api-8f78adcddb4d)

**1Password Connect**:
- [1Password Connect Operator](https://github.com/1Password/onepassword-operator)
- [1Password Connect Kubernetes](https://developer.1password.com/docs/connect/kubernetes/)

### Haus Work Environment Files

**For Reference** (read-only, don't modify):
- `/Users/martindelisle/code/Haus/gitops-argocd/clusters/haus-prod/dex/kustomization.yaml`
- `/Users/martindelisle/code/Haus/gitops-argocd/clusters/haus-prod/dex/manifests/`
- `/Users/martindelisle/code/Haus/gitops-argocd/clusters/haus-prod/argo-workflows/kustomization.yaml` (lines 81-109)
- `/Users/martindelisle/code/Haus/gitops-argocd/components/core/argocd/patches/patch-argocd-rbac-cm.yaml`

---

## Next Steps (When Ready to Implement)

### Pre-Implementation Checklist

- [ ] Time available: 4-8 hours over 1-2 days
- [ ] Google Cloud Console access (for OAuth client creation)
- [ ] 1Password access (for secret storage)
- [ ] Homeops git repo clean (no uncommitted changes)
- [ ] Cluster access verified (`kubectl get nodes`)
- [ ] Review this document fully

### Implementation Session 1 (2-4 hours)

**Focus**: Dex Deployment
1. Create Google OAuth Client
2. Store credentials in 1Password
3. Create Dex manifests
4. Deploy via ArgoCD
5. Test Dex endpoints

### Implementation Session 2 (1-2 hours)

**Focus**: Temporal Integration
1. Generate Temporal client secret
2. Update Temporal Helm values
3. Create OnePasswordItem
4. Deploy and test login flow

### Implementation Session 3 (Optional, 1-2 hours)

**Focus**: Additional Services
1. ArgoCD OIDC integration
2. Test and validate

---

## Notes & Considerations

### Security Considerations

1. **OAuth Client Secrets**: Never commit to git, always in 1Password
2. **JWT Validation**: Dex handles this, applications must validate Dex JWTs
3. **Callback URLs**: Must match exactly (HTTPS required)
4. **Session Management**: Applications handle their own sessions after JWT validation

### Future Enhancements

1. **RBAC Implementation**: Map email/groups to roles
2. **Multiple Identity Providers**: Add GitHub as secondary IdP
3. **Gateway API Migration**: When k3s support improves
4. **Observability**: Add metrics/logging for authentication events
5. **Service Account Auth**: For programmatic access (CI/CD)

### Known Limitations

1. **No k3s Gateway API**: Staying with Traefik/Ingress for now
2. **No Group Sync**: Personal Google account may not have Groups API
3. **Single User**: Currently only you, but architecture supports multiple
4. **No MFA Enforcement**: Relies on Google account MFA

---

## Questions & Decisions Log

**Q**: Why Google over GitHub?
**A**: Better OIDC implementation, consistent with work setup, groups support (future), mature OAuth provider

**Q**: Why 1Password over Sealed Secrets?
**A**: More native, centralized secret management, easier rotation, better audit trail, already using for GitHub App

**Q**: Why not Cloudflare Access JWT pass-through?
**A**: Cloudflare Access doesn't pass JWT assertions to applications in homeops setup, would need re-architecture

**Q**: When to migrate to Gateway API?
**A**: Later, when k3s has native support or when willing to invest in manual Traefik configuration / CNI replacement

**Q**: Can we skip Dex and use Google directly?
**A**: Yes, but Dex provides flexibility (multiple IdPs, custom claims, protocol translation). Recommended for consistency with work setup.

---

## Document Maintenance

**Last Updated**: January 20, 2026
**Next Review**: When ready to implement (estimated few weeks)
**Owner**: Martin
**Status**: Planning - Ready for Implementation

**Update Log**:
- 2026-01-20: Initial creation based on discovery session
- Future: Update with actual implementation experiences

---

**End of Document**
