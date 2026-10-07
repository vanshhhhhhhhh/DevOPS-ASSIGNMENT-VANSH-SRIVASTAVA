#!/usr/bin/env bash
# Rehearsal of demo.sh BEFORE the GitHub repo exists.
# Packages ../app as a Helm chart (namespace renamed to s20-gitops-rehearsal), serves it
# from an in-cluster chart repo, runs ../demo.sh against rehearsal-application.yaml,
# then deletes everything it created. Needs: kubectl, helm, Argo CD in namespace argocd.
set -euo pipefail
cd "$(dirname "$0")"
TMP=$(mktemp -d)
REPO_URL=http://s20-chartrepo.s20-gitops-chartrepo.svc.cluster.local:8080

echo "--- packaging ../app as Helm chart s20-web 0.1.0"
mkdir -p "$TMP/chart/templates" "$TMP/repo"
cat > "$TMP/chart/Chart.yaml" <<YAML
apiVersion: v2
name: s20-web
version: 0.1.0
description: Session 20 GitOps demo app (rehearsal copy of 03-gitops/app)
YAML
for f in ../app/*.yaml; do
  sed 's/s20-gitops-demo/s20-gitops-rehearsal/g' "$f" > "$TMP/chart/templates/$(basename "$f")"
done
helm package "$TMP/chart" -d "$TMP/repo"
helm repo index "$TMP/repo" --url "$REPO_URL"

echo "--- starting the in-cluster chart repo"
kubectl create namespace s20-gitops-chartrepo
kubectl create configmap s20-chartrepo -n s20-gitops-chartrepo --from-file="$TMP/repo/"
kubectl apply -f chart-server.yaml
kubectl rollout status deployment/s20-chartrepo -n s20-gitops-chartrepo --timeout=120s

echo "--- running ../demo.sh against the rehearsal Application"
APP_FILE=rehearsal/rehearsal-application.yaml ../demo.sh

echo "--- cleaning up the rehearsal"
kubectl delete -f rehearsal-application.yaml --wait=true
kubectl delete namespace s20-gitops-rehearsal --ignore-not-found --wait=true
kubectl delete namespace s20-gitops-chartrepo --wait=true
rm -rf "$TMP"
