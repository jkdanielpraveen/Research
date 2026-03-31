#!/usr/bin/env bash
set -euo pipefail

# Next AWX recovery checks after metrics-server is healthy.

kubectl -n awx describe awx awx-demo
kubectl -n awx get pods -o wide
kubectl -n awx get events --sort-by='.lastTimestamp'
kubectl -n awx logs deployment/awx-operator-controller-manager -c awx-manager --tail=400

# Watch for AWX pods to appear and become Ready.
kubectl -n awx get pods -w

# Once AWX pods are running, retrieve the auto-generated admin password.
kubectl -n awx get secret awx-demo-admin-password -o jsonpath='{.data.password}' | base64 --decode; echo
