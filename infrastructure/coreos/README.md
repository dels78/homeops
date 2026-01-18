# Fedora CoreOS Node Provisioning

Zero-touch provisioning for k3s cluster nodes using Fedora CoreOS and Ignition.

## Prerequisites

```bash
# Install butane (Fedora CoreOS config transpiler)
brew install butane

# Get the k3s cluster token (from existing control-plane node)
ssh core@<master-node> 'sudo cat /var/lib/rancher/k3s/server/token'
```

## Quick Start

### 1. Set up environment

```bash
cd infrastructure/coreos

# Create .env file with your token (gitignored)
# Copy from .env.example and fill in values
cp .env.example .env
```

### 2. Generate ignition config

```bash
./build-ignition.sh my-new-node

# Output in ./output/my-new-node.ign
```

### 3. Install Fedora CoreOS

Download the live ISO from: https://fedoraproject.org/coreos/download

Boot the target machine from the ISO, then:

```bash
# Option A: Serve ignition via HTTP (recommended)
# On your workstation:
cd output && python3 -m http.server 8080

# On the target machine:
sudo coreos-installer install /dev/sda \
  --ignition-url http://<your-workstation-ip>:8080/my-new-node.ign

# Option B: Copy ignition file directly (USB, etc.)
sudo coreos-installer install /dev/sda \
  --ignition-file /path/to/my-new-node.ign
```

### 4. Reboot and verify

After installation completes, reboot the machine. It will:

1. Boot into Fedora CoreOS
2. Install `k3s-selinux` package
3. Download and install k3s agent
4. Join the cluster automatically

Verify from your workstation:

```bash
kubectl get nodes
# Should show new node after a few minutes
```

## Files

| File | Purpose |
|------|---------|
| `agent-node.bu.template` | Butane template for agent nodes |
| `build-ignition.sh` | Script to generate ignition configs |
| `.env` | Local secrets (gitignored) |
| `.env.example` | Example env file |
| `output/` | Generated configs (gitignored) |

## Template Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `{{HOSTNAME}}` | Node hostname | (required) |
| `{{K3S_TOKEN}}` | Cluster join token | from `.env` |
| `{{K3S_SERVER}}` | K3s API server URL | from `.env` |
| `{{SSH_PUBKEY}}` | SSH public key | `~/.ssh/id_ed25519.pub` |

## What Gets Configured

The ignition config sets up:

- **User**: `core` with SSH key authentication
- **Hostname**: As specified
- **k3s-selinux**: Installed via rpm-ostree on first boot
- **k3s agent**: Installed and joined to cluster on first boot
- **Zincati**: Automatic OS updates (built into FCOS)
- **Console autologin**: For easier debugging

## Adding a Server Node

For a new control-plane node (rare), modify the template:

```yaml
# In run-k3s-installer script, change:
curl -sfL https://get.k3s.io | K3S_TOKEN={{K3S_TOKEN}} sh -s - server \
  --server {{K3S_SERVER}} \
  --disable servicelb \
  --disable traefik
```

## Troubleshooting

### Node doesn't join cluster

SSH to the node and check:

```bash
# Check k3s installer service
sudo journalctl -u run-k3s-installer.service

# Check k3s agent service
sudo journalctl -u k3s-agent

# Verify network connectivity to server
curl -k ${K3S_SERVER}
```

### k3s-selinux installation failed

```bash
# Check rpm-ostree service
sudo journalctl -u rpm-ostree-install-k3s-selinux.service

# Manual install
sudo rpm-ostree install k3s-selinux
sudo systemctl reboot
```
