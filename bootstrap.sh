#!/bin/bash
set -e

# bootstrap script - run this once.
# after this, Argo CD will manage itself using the root app.

ARGOCD_VERSION="v2.12.0"
REPO_URL="https://github.com/harikrishnanaik/argocd-gitops"

echo "==> creating the argocd namespace"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo "==> installing Argo CD ${ARGOCD_VERSION}"
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml

echo "==> waiting for Argo CD to become ready (this can take a couple minutes)"
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=300s

echo "==> reading the initial admin password"
INITIAL_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
echo "    initial password: ${INITIAL_PASS}"

echo ""
echo "==> applying root app (bootstrapping the rest of the repo)"
# make sure you update the repo URL in apps/root-app.yaml first
kubectl apply -f apps/root-app.yaml

echo ""
echo "done! Argo CD should now manage itself and deploy Prometheus"
echo "open the UI with: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "login: admin / ${INITIAL_PASS}"
echo ""
echo "NOTE: I replaced the repo URL placeholders with your username."
