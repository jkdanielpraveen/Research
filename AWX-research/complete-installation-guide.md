# AWX 23 — Defaults-only, copy-paste installation (k3s + awx-operator 2.10.0)

This file contains a single, default-only, copy-pasteable command sequence you can run on a Rocky Linux 9 server to install a single-node k3s cluster and deploy AWX via the pinned `awx-operator:2.10.0`.

Goal: after running the commands below (no interactive choices, no manual secrets), the AWX Web UI will be reachable at a Node IP + NodePort and the operator will have created auto-generated secrets for the admin account.

What we learned during the actual lab run:
- The operator deployment initially failed because one sidecar image referenced `gcr.io/kubebuilder/kube-rbac-proxy:v0.15.0`; replacing it with `quay.io/brancz/kube-rbac-proxy:v0.21.2` fixed the rollout.
- AWX reconciliation did not complete until `metrics-server` became healthy and `v1beta1.metrics.k8s.io` reported `Available=True`.
- On this Rocky Linux host, disabling `firewalld` was the fastest way to let metrics-server reach kubelet on port `10250`.
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

# If the operator pod fails because kube-rbac-proxy points at a dead gcr.io image,
# patch the controller-manager deployment and replace the kube-rbac-proxy image with:
# quay.io/brancz/kube-rbac-proxy:v0.21.2

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

# 6) Wait for AWX pods to be created and reach Running
echo "Waiting for awx-demo pods to reach Running state (this can take several minutes)..."
MAX_WAIT=900
SLEEP=10
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
  if kubectl get pods -n awx | awk '/^awx-demo/ && $3=="Running" {exit 0} END{exit 1}'; then
    echo "awx-demo pod is Running"
    break
  fi
  sleep $SLEEP
  ELAPSED=$((ELAPSED+SLEEP))
  printf '.'
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
  echo
  echo "Timeout waiting for awx-demo pods. Check operator logs:" >&2
  echo "  kubectl -n awx logs deployment/awx-operator-controller-manager -c awx-manager --tail=200" >&2
  exit 2
fi

# 7) Get NodePort and print UI URL
NODE_PORT=$(kubectl get svc -n awx awx-demo-service -o jsonpath='{.spec.ports[0].nodePort}') || true
if [ -z "$NODE_PORT" ]; then
  echo "Could not find awx-demo-service NodePort yet. Listing services:";
  kubectl get svc -n awx
  exit 3
fi

# Determine node IP (first non-loopback address)
NODE_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
if [ -z "$NODE_IP" ]; then
  NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
fi

echo
echo "AWX Web UI should be available at: http://${NODE_IP}:${NODE_PORT}"
echo "Default admin user: admin"
echo "To retrieve the auto-generated admin password run:" 
echo "  kubectl get secret awx-demo-admin-password -n awx -o jsonpath=\"{.data.password}\" | base64 --decode ; echo"

echo
echo "If the UI is not reachable, view operator logs and AWX CR status:" 
echo "  kubectl -n awx logs deployment/awx-operator-controller-manager -c awx-manager -f"
echo "  kubectl get awx awx-demo -n awx -o yaml"

echo "Install finished (script end)"
```

If the operator gets stuck again after `metrics-server` is healthy, force a fresh reconcile and watch the pods/logs with these exact commands:

```bash
kubectl -n awx annotate awx awx-demo awx.ansible.com/reconcile="$(date +%s)" --overwrite
kubectl -n awx get awx awx-demo -o yaml
kubectl -n awx get pods -w
kubectl -n awx logs deployment/awx-operator-controller-manager -c awx-manager -f
```

When AWX finishes, the password secret is the admin password for the AWX UI:

```bash
kubectl -n awx get secret awx-demo-admin-password -o jsonpath='{.data.password}' | base64 --decode; echo
```

The AWX web URL is the Node IP plus the `awx-demo-service` NodePort. On the lab host this resolved to:

```bash
http://192.168.29.199:30153
```

If you need to derive the URL on another host, use:

```bash
NODE_PORT=$(kubectl -n awx get svc awx-demo-service -o jsonpath='{.spec.ports[0].nodePort}')
NODE_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo "http://${NODE_IP}:${NODE_PORT}"
```

Notes & troubleshooting (quick):
- If the install hangs, check operator logs (above) and `kubectl get events -n awx --sort-by='.lastTimestamp'`.
- If CRDs existed from a prior different operator version, delete them and reapply the pinned `2.10.0` kustomize resources.
- For production, do not use k3s single-node and provide external Postgres; this script is for a single-server non-HA install.

If `metrics.k8s.io/v1beta1` is `False (MissingEndpoints)` and `metrics-server` is stuck at `0/1`, run these exact commands:

```bash
kubectl -n kube-system describe pod metrics-server-c8774f4f4-c626s
kubectl -n kube-system logs pod/metrics-server-c8774f4f4-c626s --tail=200
kubectl -n kube-system get events --sort-by='.lastTimestamp'
kubectl -n kube-system get deployment metrics-server -o yaml | sed -n '/containers:/,/volumes:/p'
```

If the metrics-server logs show kubelet TLS or certificate errors, or if it cannot reach kubelet on `10250`, patch the deployment with these exact arguments:

```bash
kubectl -n kube-system edit deployment metrics-server
```

Add these lines under the `metrics-server` container `args:` list:

```yaml
- --kubelet-insecure-tls
- --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
```

Then run:

```bash
kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s
kubectl get apiservice v1beta1.metrics.k8s.io
```

If metrics-server still logs `no route to host` for `https://<node-ip>:10250/metrics/resource`, open the kubelet port on the Rocky host or disable firewalld for the lab install:

```bash
sudo firewall-cmd --permanent --add-port=10250/tcp
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --reload
```

If you want the simplest lab setup, disable firewalld entirely before retrying:

```bash
sudo systemctl disable firewalld --now
```

After that, force a reconcile and then run these exact commands:

```bash
kubectl -n awx annotate awx awx-demo awx.ansible.com/reconcile="$(date +%s)" --overwrite
kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl -n awx get awx
kubectl -n awx get pods -w
kubectl -n awx logs deployment/awx-operator-controller-manager -c awx-manager -f
kubectl -n awx get secret awx-demo-admin-password -o jsonpath='{.data.password}' | base64 --decode; echo
```

If the AWX custom resource is present and you want to watch reconciliation after metrics-server is fixed:

```bash
kubectl -n awx get awx
kubectl -n awx describe awx awx-demo
kubectl -n awx get pods -w
kubectl -n awx logs deployment/awx-operator-controller-manager -c awx-manager -f
kubectl -n awx get secret awx-demo-admin-password -o jsonpath='{.data.password}' | base64 --decode; echo
```

Saved files:
- `$HOME/awx-install/kustomization.yaml`
- `$HOME/awx-install/awx-demo.yml`

If you want, I can also produce a single executable script file under `AWX-research/` you can `scp` to the server and run as one script — tell me if you want that next.
