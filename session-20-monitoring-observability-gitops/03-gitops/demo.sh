#!/usr/bin/env bash
# Session 20 GitOps demo with Argo CD.
#
# Run this AFTER the repo has been pushed to GitHub (Argo CD pulls the manifests
# from github.com/vanshhhhhhhhh/DevOPS-ASSIGNMENT-VANSH-SRIVASTAVA, branch main,
# path session-20-monitoring-observability-gitops/03-gitops/app).
#
#   1. applies the Argo CD Application (the only manual kubectl apply)
#   2. waits until Argo CD reports Synced / Healthy
#   3. shows what Argo CD created, and the app's visible version string
#   4. demonstrates self-heal: scales the Deployment and deletes the Service
#      by hand, then shows Argo CD putting both back to what Git says
#   5. prints Argo CD's sync history and events
#
# Requirements: kubectl pointing at the cluster, Argo CD installed in namespace argocd,
# curl, and local port 8300 free (override with LOCAL_PORT).
# APP_FILE can point at a different Application manifest (used for the rehearsal).
set -euo pipefail
cd "$(dirname "$0")"

APP_FILE="${APP_FILE:-argocd-application.yaml}"
DEPLOY="${DEPLOY:-s20-web}"
SVC="${SVC:-s20-web}"
LOCAL_PORT="${LOCAL_PORT:-8300}"
TIMEOUT="${TIMEOUT:-300}"

APP=$(kubectl create --dry-run=client -o jsonpath='{.metadata.name}' -f "$APP_FILE")
NS=$(kubectl create --dry-run=client -o jsonpath='{.spec.destination.namespace}' -f "$APP_FILE")

step() { printf '\n========== %s ==========\n' "$*"; }
run()  { echo "\$ $*"; "$@"; }
app_status() {
  kubectl get application "$APP" -n argocd \
    -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || true
}

step "0. Argo CD is running in namespace argocd"
run kubectl get pods -n argocd

step "1. Apply the Argo CD Application ($APP_FILE)"
run kubectl apply -f "$APP_FILE"

step "2. Wait for Synced / Healthy (timeout ${TIMEOUT}s)"
deadline=$((SECONDS + TIMEOUT))
while :; do
  s=$(app_status)
  [[ "$s" == "/" ]] && s=""
  echo "  $(date +%H:%M:%S)  sync/health = ${s:-<not reported yet>}"
  [[ "$s" == "Synced/Healthy" ]] && break
  if (( SECONDS >= deadline )); then
    echo "Timed out. Application conditions:"
    kubectl get application "$APP" -n argocd -o jsonpath='{.status.conditions}'; echo
    exit 1
  fi
  sleep 5
done
run kubectl get application "$APP" -n argocd
echo "synced revision: $(kubectl get application "$APP" -n argocd -o jsonpath='{.status.sync.revision}{.status.sync.revisions}')"

step "3. Resources Argo CD created from the source"
run kubectl get all -n "$NS"
echo "\$ kubectl get application $APP -n argocd -o jsonpath='{range .status.resources[*]}...'"
kubectl get application "$APP" -n argocd \
  -o jsonpath='{range .status.resources[*]}{.kind}{"\t"}{.name}{"\t"}{.status}{"\t"}{.health.status}{"\n"}{end}'

kubectl port-forward -n "$NS" "svc/$SVC" "$LOCAL_PORT:80" >/dev/null 2>&1 &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null || true' EXIT
for _ in $(seq 1 20); do curl -fs "http://localhost:$LOCAL_PORT/version.json" >/dev/null 2>&1 && break; sleep 1; done
run curl -s "http://localhost:$LOCAL_PORT/version.json"
run curl -s "http://localhost:$LOCAL_PORT/"
kill $PF_PID 2>/dev/null || true
wait $PF_PID 2>/dev/null || true

step "4a. Self-heal: change the replica count by hand (drift from the desired state)"
desired=$(kubectl get deploy "$DEPLOY" -n "$NS" -o jsonpath='{.spec.replicas}')
echo "desired replicas (from source): $desired"
run kubectl scale deployment "$DEPLOY" -n "$NS" --replicas=5
for i in $(seq 1 30); do
  r=$(kubectl get deploy "$DEPLOY" -n "$NS" -o jsonpath='{.spec.replicas}')
  echo "  $(date +%H:%M:%S)  spec.replicas=$r   argocd sync/health=$(app_status)"
  [[ "$r" == "$desired" ]] && break
  sleep 2
done
run kubectl get deployment "$DEPLOY" -n "$NS"

step "4b. Self-heal: delete the Service by hand"
run kubectl delete service "$SVC" -n "$NS"
for i in $(seq 1 30); do
  if kubectl get service "$SVC" -n "$NS" >/dev/null 2>&1; then
    echo "  $(date +%H:%M:%S)  service/$SVC exists again"
    break
  fi
  echo "  $(date +%H:%M:%S)  service/$SVC missing   argocd sync/health=$(app_status)"
  sleep 2
done
run kubectl get service "$SVC" -n "$NS"

step "5. Argo CD's record of what happened"
sleep 5
run kubectl get application "$APP" -n argocd
echo "\$ kubectl get application $APP -n argocd -o jsonpath='{range .status.history[*]}...'"
kubectl get application "$APP" -n argocd \
  -o jsonpath='{range .status.history[*]}id={.id}  revision={.revision}{.revisions}  deployedAt={.deployedAt}{"\n"}{end}'
echo "last operation: $(kubectl get application "$APP" -n argocd -o jsonpath='{.status.operationState.phase} - {.status.operationState.message}')"
# filter on this Application's UID, so events left over from an older
# Application with the same name are not shown
APP_UID=$(kubectl get application "$APP" -n argocd -o jsonpath='{.metadata.uid}')
run kubectl get events -n argocd --field-selector "involvedObject.uid=$APP_UID" \
  --sort-by=.lastTimestamp -o custom-columns=TIME:.lastTimestamp,REASON:.reason,MESSAGE:.message

echo
echo "Done. The Application stays in place; Argo CD keeps reconciling $NS from the source."
echo "Clean up with: kubectl delete -f $APP_FILE && kubectl delete namespace $NS"
