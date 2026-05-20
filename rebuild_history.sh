#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Fixing repository URLs..."
sed -i 's/harikrishnanaik\/argocd-gitops/harikrishnanaik13-jpg\/argocd-gitops/g' \
  apps/root-app.yaml \
  apps/argocd-app.yaml \
  apps/prometheus-app.yaml \
  apps/argocd-monitoring-app.yaml \
  bootstrap.sh

echo "Creating staged commits..."
git checkout -B fix/repo-urls

git add apps/root-app.yaml apps/argocd-app.yaml apps/prometheus-app.yaml apps/argocd-monitoring-app.yaml
if git diff --cached --quiet; then
  echo "No changes to commit for app manifests."
else
  git commit -m "fix(apps): correct repo URLs for correct GitHub username"
fi

git add bootstrap.sh
if git diff --cached --quiet; then
  echo "No changes to commit for bootstrap.sh."
else
  git commit -m "chore(bootstrap): update REPO_URL to the correct GitHub username"
fi

git add README.md
if git diff --cached --quiet; then
  echo "No changes to commit for README.md."
else
  git commit -m "docs(readme): fix quick start and end-to-end flow rendering"
fi

echo "Done. Review the new history with: git log --oneline --decorate --graph --all"