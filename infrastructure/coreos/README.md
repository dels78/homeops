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

## Serving Ignition via Kubernetes

If macOS firewall blocks the local HTTP server, serve via a temp pod:

```bash
# Create configmap and pod
kubectl create configmap node-ignition --from-file=node.ign=output/my-new-node.ign
kubectl run ignition-server --image=nginx:alpine --restart=Never --overrides='
{
  "spec": {
    "containers": [{
      "name": "ignition-server",
      "image": "nginx:alpine",
      "ports": [{"containerPort": 80}],
      "volumeMounts": [{"name": "ignition", "mountPath": "/usr/share/nginx/html"}]
    }],
    "volumes": [{"name": "ignition", "configMap": {"name": "node-ignition"}}]
  }
}'
kubectl expose pod ignition-server --type=NodePort --port=80

# Get the URL
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
NODE_PORT=$(kubectl get svc ignition-server -o jsonpath='{.spec.ports[0].nodePort}')
echo "http://${NODE_IP}:${NODE_PORT}/node.ign"

# Cleanup after install
kubectl delete pod ignition-server && kubectl delete svc ignition-server && kubectl delete configmap node-ignition
```

## Promoting Agent to Server

To convert an existing agent node to a control-plane node:

```bash
# 1. Delete the node from kubernetes
kubectl delete node <node-name>

# 2. On the node, uninstall k3s agent
sudo /usr/local/bin/k3s-agent-uninstall.sh

# 3. Reinstall as server
curl -sfL https://get.k3s.io | K3S_TOKEN='<token>' sh -s - server --server https://<control-plane-ip>:6443

# 4. Start the service
sudo systemctl start k3s

# 5. Add label for system-upgrade-controller
kubectl label node <node-name> node-role.kubernetes.io/master=true
```

## Removing a Server Node

To remove a dead/failed control-plane node:

```bash
# 1. Create etcd backup
ssh core@<healthy-node> 'sudo k3s etcd-snapshot save --name pre-removal'

# 2. Get etcd member ID
ssh core@<healthy-node> 'curl -sL https://github.com/etcd-io/etcd/releases/download/v3.5.9/etcd-v3.5.9-linux-amd64.tar.gz | sudo tar xzf - -C /tmp etcd-v3.5.9-linux-amd64/etcdctl'
ssh core@<healthy-node> "sudo /tmp/etcd-v3.5.9-linux-amd64/etcdctl \
  --endpoints='https://127.0.0.1:2379' \
  --cacert='/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt' \
  --cert='/var/lib/rancher/k3s/server/tls/etcd/server-client.crt' \
  --key='/var/lib/rancher/k3s/server/tls/etcd/server-client.key' \
  member list -w table"

# 3. Remove from etcd (use member ID from above)
ssh core@<healthy-node> "sudo /tmp/etcd-v3.5.9-linux-amd64/etcdctl \
  --endpoints='https://127.0.0.1:2379' \
  --cacert='/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt' \
  --cert='/var/lib/rancher/k3s/server/tls/etcd/server-client.crt' \
  --key='/var/lib/rancher/k3s/server/tls/etcd/server-client.key' \
  member remove <member-id>"

# 4. Delete from kubernetes
kubectl delete node <node-name>

# 5. Cleanup temp etcdctl
ssh core@<healthy-node> 'sudo rm -rf /tmp/etcd-v3.5.9-linux-amd64'
```

## System Upgrade Controller

Server nodes need the `control-plane` label for automatic upgrades. New k3s versions set this by default, but if a node isn't upgrading:

```bash
# Check labels
kubectl get node <node> --show-labels | grep -E 'master|control-plane'

# Add if missing (for server nodes)
kubectl label node <node> node-role.kubernetes.io/master=true
```

## Troubleshooting

### Node doesn't join cluster

SSH to the node and check:

```bash
# Check k3s installer service
sudo journalctl -u run-k3s-installer.service

# Check k3s agent service (or k3s for servers)
sudo journalctl -u k3s-agent
sudo journalctl -u k3s

# Verify network connectivity to server
curl -k ${K3S_SERVER}
```

**Tip**: If the primary control-plane node is degraded, try pointing to a different healthy control-plane node.

### k3s-selinux installation failed

```bash
# Check rpm-ostree service
sudo journalctl -u rpm-ostree-install-k3s-selinux.service

# Manual install
sudo rpm-ostree install k3s-selinux
sudo systemctl reboot
```

### SSH key not found

The build script looks for `~/.ssh/id_ed25519.pub` by default. If using 1Password SSH agent, get the key from an existing node:

```bash
ssh core@<existing-node> 'cat ~/.ssh/authorized_keys.d/*'
# Add to .env as SSH_PUBKEY="..."
```
