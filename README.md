# homeops

[![FOSSA Status](https://app.fossa.com/api/projects/git%2Bgithub.com%2Fdels78%2Fhomeops.svg?type=shield)](https://app.fossa.com/projects/git%2Bgithub.com%2Fdels78%2Fhomeops?ref=badge_shield)

This repository is my home playground!

GitOps/ArgoCD managed k3s cluster to host home applications!

## Cluster Infrastructure

- **Nodes**: Fedora CoreOS on mini PCs
- **Orchestration**: k3s (lightweight Kubernetes)
- **GitOps**: ArgoCD for application deployment
- **Ingress**: Traefik + Cloudflare Zero Trust

### Node Provisioning

New cluster nodes can be provisioned using the butane/ignition configs in [`infrastructure/coreos/`](infrastructure/coreos/README.md). This provides zero-touch setup - boot from Fedora CoreOS live ISO, install with ignition config, and the node automatically joins the k3s cluster.

## Applications

Applications are deployed via ArgoCD. See [`argocd/applications/`](argocd/applications/) for the full list.

## Access

All ingresses are behind Cloudflare Zero Trust which requires either my home IP or GitHub authentication to view.

## License
[![FOSSA Status](https://app.fossa.com/api/projects/git%2Bgithub.com%2Fdels78%2Fhomeops.svg?type=large)](https://app.fossa.com/projects/git%2Bgithub.com%2Fdels78%2Fhomeops?ref=badge_large)