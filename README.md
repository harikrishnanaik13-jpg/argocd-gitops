# argocd-gitops

Welcome to my Argo CD GitOps demo. This repo is built to show a real-world way to make Argo CD manage itself, plus add Prometheus/Grafana monitoring on top.

## what this is

- Argo CD installs itself and then keeps its own config in Git
- Prometheus and Grafana are deployed to watch Argo CD
- Argo CD repo-server uses a newer Helm binary via an init container

## how the repo is laid out

```
.
├── apps/                    # the root app and the two child apps
│   ├── root-app.yaml        # the app-of-apps that bootstraps everything
│   ├── argocd-app.yaml      # Argo CD self-management
│   └── prometheus-app.yaml  # Prometheus + monitoring stack
├── argocd/
│   └── install/
│       ├── kustomization.yaml
│       └── patches/
│           └── repo-server-helm-override.yaml   # replace Helm in repo-server
├── prometheus/
│   ├── values.yaml                    # Helm values for kube-prometheus-stack
│   ├── argocd-servicemonitor.yaml     # tells Prometheus how to scrape Argo CD
│   ├── argocd-dashboards-configmap.yaml
│       # Grafana dashboards for Argo CD
│   └── argocd-alerts.yaml
└── bootstrap.sh             # run this first to get the repo going
```

## before you start

This repo assumes you are using GitHub. Replace `YOUR_USERNAME` with your GitHub username in:

- `apps/root-app.yaml`
- `apps/argocd-app.yaml`

That is the only change you need before pushing the repo and bootstrapping.

## quick start

1. commit the repo and push it to GitHub

```bash
git add .
git commit -m "initial commit"
git push
```

2. run the bootstrap script

```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

That installs Argo CD into the cluster, waits for the server to be ready, and then applies `apps/root-app.yaml`. From there, Argo CD takes over and deploys everything else.

## open the UIs

Argo CD:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Then open `https://localhost:8080` and log in as:

- user: `admin`
- password: printed by `bootstrap.sh`

Grafana:

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
```

Open `http://localhost:3000` and log in with:

- user: `admin`
- password: `changeme123`

The Argo CD dashboard appears under `Dashboards > ArgoCD > ArgoCD Overview`.

---

## how self-management works

This repo uses the app-of-apps pattern.

- `apps/root-app.yaml` is the top-level Argo CD Application.
- It points at the `apps/` folder in this repo.
- Argo CD reads that folder and creates child apps for `argocd-app.yaml` and `prometheus-app.yaml`.

So the flow is:

```
repo
└── apps/
    ├── root-app.yaml   # watched by Argo CD
    ├── argocd-app.yaml # manages Argo CD install
    └── prometheus-app.yaml # manages monitoring stack
```

That means Argo CD is now managing its own installation from `argocd/install/`. If you want to change Argo CD config, edit the Git repo and push. Argo CD will apply the change.

---

## Helm override

Argo CD repo-server ships with a built-in Helm binary. I chose to replace that with Helm `3.14.4` using an init container.

The init container downloads the requested Helm release and places it into an `emptyDir` volume. The repo-server then mounts that volume over `/usr/local/bin/helm`, which hides the built-in version.

The override is defined in `argocd/install/patches/repo-server-helm-override.yaml` and is applied through Kustomize.

To confirm it worked:

```bash
kubectl exec -n argocd deploy/argocd-repo-server -- helm version
```

If you want a different Helm version, change the `HELM_VERSION` variable in the patch.

---

## Prometheus monitoring

Argo CD exposes metrics on the following ports by default:

- `8082` for the application controller
- `8083` for the repo-server
- `8084` for the Argo CD server

This repo adds ServiceMonitors so Prometheus can scrape those endpoints. The labels on those ServiceMonitors are aligned with the `kube-prometheus-stack` instance.

In `prometheus/values.yaml`, `serviceMonitorSelectorNilUsesHelmValues: false` is set so the Prometheus instance will find ServiceMonitors across namespaces.

The alerts in `prometheus/argocd-alerts.yaml` cover things like:

- application out of sync for more than 10 minutes
- degraded app health
- sync failures
- repo-server downtime
- high reconciliation latency

---

## assumptions

- You are using a Kubernetes cluster such as kind or k3s.
- The cluster has enough capacity for Argo CD and kube-prometheus-stack.
- GitHub is the repo provider in this example.
- If your cluster does not have a default storage class, you may need to adjust persistence or add one.

---

## troubleshooting

### Argo CD app stuck in `Progressing`

Run:

```bash
argocd app get <appname>
kubectl describe application <appname> -n argocd
```

Look for failed resources, RBAC issues, or missing CRDs.

### ServiceMonitors not being picked up

Check the Prometheus selector:

```bash
kubectl get prometheus -n monitoring -o yaml | grep -A10 serviceMonitorSelector
```

If the selector is strict, your ServiceMonitor labels must match it.

### Helm override not working

Check logs and verify the Helm version:

```bash
kubectl logs -n argocd deploy/argocd-repo-server -c download-helm
kubectl exec -n argocd deploy/argocd-repo-server -- helm version
```

If your cluster has no internet access, the init container cannot download Helm.

### Prometheus cannot scrape Argo CD

Check the Argo CD services first:

```bash
kubectl get svc -n argocd
kubectl get servicemonitor -n monitoring
```

### Argo CD won't self-heal after manual edits

Make sure `selfHeal: true` is enabled and make changes in Git, not directly in the cluster.

### `ComparisonError` in Argo CD

That usually means Argo CD cannot reach the Git repo. Run:

```bash
argocd repo list
```

Verify the repo URL and credentials.

---

## end-to-end GitOps flow

When an Argo CD application has automated sync enabled and you push a commit, the path looks like this:

```text
developer pushes commit to git
        │
        │  (Argo CD polls git periodically, or uses webhooks)
        ▼
  Argo CD repo-server
    - clones or fetches the repo
    - checks the manifest definitions
    - applies the desired state to the cluster
```


When an Argo CD app is set to automated sync and you push a git change:

```
developer pushes commit to git
        │
        │  (Argo CD polls git periodically, or uses webhooks)
        ▼
  Argo CD repo-server
    - clones or fetches the repo
```
    - renders the manifests (helm template / kustomize build / plain yaml)
    - returns rendered manifests to application-controller
        │
        ▼
  application-controller
    - compares rendered manifests against live cluster state
      (it queries kube-apiserver to get current state)
    - detects a diff (OutOfSync)
    - since auto-sync is enabled, triggers a sync
        │
        ▼
  argocd-server (the API/UI layer)
    - handles the sync request
    - calls repo-server again to get the final manifests
        │
        ▼
  kube-apiserver
    - application-controller applies the manifests
    - kubectl apply basically (uses server-side apply)
    - kube-apiserver writes to etcd and schedules whatever changed
        │
        ▼
  application-controller
    - watches the resources it just applied
    - polls health status (checks deployment rollout, pod status, etc.)
    - updates the Application resource status
    - once everything is healthy: marks app as Synced + Healthy
```

**the reconciliation loop**

application-controller runs a reconciliation loop. every ~3 minutes (configurable) it:
1. asks repo-server for the desired state from git
2. asks kube-apiserver for the current live state
3. compares them
4. if different AND auto-sync is on: syncs

**git polling vs webhooks**

by default argocd polls git every 3 minutes. you can configure a webhook from github/gitlab to hit `https://<argocd-server>/api/webhook` to trigger an immediate refresh when a commit is pushed. way faster and less load on git.

**what repo-server actually does**

repo-server is stateless but caches git repos locally. it handles:
- cloning repos (with credentials if needed)
- running `helm template` or `kustomize build` or just reading yaml files
- returning the rendered manifests

it does NOT directly talk to the cluster - thats the application-controller's job.

**selfHeal**

with selfHeal enabled, application-controller also watches live resources using k8s watches (not just polling). if someone does `kubectl edit` on something argocd manages, argocd gets notified immediately via the watch and reverts it. this is the "drift detection" part.
