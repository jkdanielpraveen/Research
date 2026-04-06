# AWX 23 — Defaults-only, copy-paste installation (k3s + awx-operator 2.10.0)

This file contains a single, default-only, copy-pasteable command sequence you can run on a Rocky Linux 9 server to install a single-node k3s cluster and deploy AWX via the pinned `awx-operator:2.10.0`.

Goal: after running the commands below (no interactive choices, no manual secrets), the AWX Web UI will be reachable at a Node IP + NodePort and the operator will have created auto-generated secrets for the admin account.

What we learned during the actual lab run:
- The operator deployment initially failed because one sidecar image referenced `gcr.io/kubebuilder/kube-rbac-proxy:v0.15.0`; replacing it with `quay.io/brancz/kube-rbac-proxy:v0.21.2` fixed the rollout.
- AWX reconciliation did not complete until `metrics-server` became healthy and `v1beta1.metrics.k8s.io` reported `Available=True`.
- On this Rocky Linux host, `firewalld` blocked metrics-server from reaching kubelet on port `10250`. The correct fix is to open the required k3s ports and patch metrics-server with `--kubelet-insecure-tls` (k3s uses a self-signed cert for kubelet).
- After metrics-server recovered, the AWX CR needed a manual reconcile annotation before the operator created the task/web pods and the admin password secret.

Files created by the commands: `$HOME/awx-install/kustomization.yaml` and `$HOME/awx-install/awx-demo.yml`.

Run these commands as a regular user with `sudo` privileges. Copy the entire block and run it, or run step-by-step if you prefer to watch progress.

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Starting AWX install (defaults-only) at $(date)"

# 1) System prep
sudo dnf update -y
sudo dnf install -y git curl wget openssl

# Make SELinux permissive for installer simplicity (recommended for lab/test).
sudo setenforce 0 || true
sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config || true

# Disable swap (kubernetes requirement)
sudo swapoff -a || true
sudo sed -i '/\sswap\s/ s/^/#/' /etc/fstab || true

# 2) Install k3s (single-node)
curl -sfL https://get.k3s.io | sh -

# Set kubeconfig for this session and copy to $HOME for convenience
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
mkdir -p "$HOME/.kube"
sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
sudo chown $(id -u):$(id -g) "$HOME/.kube/config"

echo "Waiting for k3s node to be Ready..."
# `kubectl get nodes -o name` returns `node/<name>` already — avoid doubling `node/`
kubectl wait --for=condition=Ready $(kubectl get nodes -o name | head -n1) --timeout=120s || true
kubectl get nodes

# Confirm storageclass (k3s normally provides local-path)
kubectl get storageclass || true

# 3) Prepare install directory and pinned kustomize manifest
INSTALL_DIR="$HOME/awx-install"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

cat > kustomization.yaml <<'KUSTOM'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - github.com/ansible/awx-operator/config/default?ref=2.10.0
images:
  - name: quay.io/ansible/awx-operator
    newTag: 2.10.0
namespace: awx
KUSTOM

# 4) Apply the awx-operator (this creates CRDs and the operator deployment)
kubectl apply -k .

# The upstream kustomize manifest references gcr.io/kubebuilder/kube-rbac-proxy:v0.15.0
# which is no longer reachable.  Patch it immediately so the rollout never stalls.
echo "Patching kube-rbac-proxy image to a working mirror..."
kubectl -n awx patch deployment awx-operator-controller-manager --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/image",
    "value": "quay.io/brancz/kube-rbac-proxy:v0.21.2"
  }
]'

echo "Waiting for awx-operator deployment to be available..."
kubectl -n awx rollout status deployment/awx-operator-controller-manager --timeout=300s

echo "Operator pods in namespace 'awx':"
kubectl get pods -n awx || true

# 5) Create AWX CR using defaults (operator will auto-generate secrets)
cat > awx-demo.yml <<'AWXCR'
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-demo
spec:
  service_type: nodeport
  ingress_type: none
AWXCR

kubectl apply -f awx-demo.yml -n awx
```

## Step 6 — Fix firewalld so metrics-server can reach kubelet

On Rocky Linux, `firewalld` blocks port `10250` which metrics-server needs to reach the kubelet. Run these commands to open the required k3s ports (keeps firewalld running):

```bash
sudo firewall-cmd --permanent --zone=trusted --add-interface=flannel.1
sudo firewall-cmd --permanent --zone=trusted --add-interface=cni0
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --permanent --add-port=10250/tcp
sudo firewall-cmd --permanent --add-port=30000-32767/tcp
sudo firewall-cmd --reload
```

## Step 7 — Patch metrics-server for k3s self-signed kubelet certs

k3s uses a self-signed cert for kubelet. metrics-server will refuse it unless patched:

```bash
kubectl -n kube-system patch deployment metrics-server --type='json' -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"},
  {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname"}
]'
```

Verify metrics-server becomes healthy:

```bash
kubectl -n kube-system rollout status deployment/metrics-server --timeout=120s
kubectl get apiservice v1beta1.metrics.k8s.io
```

Wait until you see `Available=True`. The AWX operator will auto-retry once metrics-server is up.

## Step 8 — Watch AWX pods come up

```bash
kubectl -n awx get pods -w
```

Wait for `awx-demo-web` and `awx-demo-task` to both show `Running`. This takes **5–15 minutes** (image pulls + Postgres init). Watch operator logs in parallel if you want to see progress:

```bash
kubectl -n awx logs deployment/awx-operator-controller-manager -c awx-manager -f
```

## Step 9 — Get the admin password and URL

```bash
kubectl -n awx get secret awx-demo-admin-password -o jsonpath='{.data.password}' | base64 --decode; echo
```

```bash
NODE_PORT=$(kubectl -n awx get svc awx-demo-service -o jsonpath='{.spec.ports[0].nodePort}')
NODE_IP=$(hostname -I | awk '{print $1}')
echo "http://${NODE_IP}:${NODE_PORT}"
```

Log in at the printed URL with username `admin` and the password from above.

## Notes & troubleshooting

- If the install hangs, check operator logs: `kubectl -n awx logs deployment/awx-operator-controller-manager -c awx-manager -f`
- Check events: `kubectl get events -n awx --sort-by='.lastTimestamp'`
- If CRDs existed from a prior different operator version, delete them and reapply the pinned `2.10.0` kustomize resources.
- For production, do not use k3s single-node and provide external Postgres; this guide is for a single-server non-HA install.

### If the operator is stuck after metrics-server is healthy

Force a fresh reconcile:

```bash
kubectl -n awx annotate awx awx-demo awx.ansible.com/reconcile="$(date +%s)" --overwrite
kubectl -n awx get pods -w
```

### If metrics-server is stuck at `0/1` / `v1beta1.metrics.k8s.io` is `False`

Check what it's complaining about:

```bash
kubectl -n kube-system logs deployment/metrics-server --tail=30
```

**Fix 1 — firewalld blocking port 10250** (most common on Rocky Linux):

```bash
sudo firewall-cmd --permanent --zone=trusted --add-interface=flannel.1
sudo firewall-cmd --permanent --zone=trusted --add-interface=cni0
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --permanent --add-port=10250/tcp
sudo firewall-cmd --permanent --add-port=30000-32767/tcp
sudo firewall-cmd --reload
```

**Fix 2 — kubelet TLS rejection** (k3s uses a self-signed cert metrics-server won't trust by default):

```bash
kubectl -n kube-system patch deployment metrics-server --type='json' -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"},
  {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname"}
]'
```

Both fixes are typically needed together. Verify after applying:

```bash
kubectl -n kube-system rollout status deployment/metrics-server --timeout=120s
kubectl get apiservice v1beta1.metrics.k8s.io
```

Saved files:
- `$HOME/awx-install/kustomization.yaml`
- `$HOME/awx-install/awx-demo.yml`

If you want, I can also produce a single executable script file under `AWX-research/` you can `scp` to the server and run as one script — tell me if you want that next.
