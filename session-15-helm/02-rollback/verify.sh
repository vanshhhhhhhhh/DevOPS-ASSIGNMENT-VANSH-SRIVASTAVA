#!/usr/bin/env bash
# Verifies the current state of the rollback-demo release:
# Helm revision history, the image actually running, and what the app serves.
# Usage: ./verify.sh [namespace] [release] [local-port]
set -euo pipefail
NS=${1:-s15-rollback}
REL=${2:-s15-rollback-demo}
PORT=${3:-18310}

kubectl rollout status deploy/"$REL"-web -n "$NS" --timeout=180s >/dev/null
# Wait until old (terminating) pods are gone so the listing below is clean.
WANT=$(kubectl get deploy "$REL"-web -n "$NS" -o jsonpath='{.spec.replicas}')
for _ in $(seq 1 60); do
  HAVE=$(kubectl get pods -n "$NS" -l app.kubernetes.io/instance="$REL" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  [ "$HAVE" = "$WANT" ] && break
  sleep 1
done

echo "\$ helm history $REL -n $NS"
helm history "$REL" -n "$NS" | column -t -s $'\t'
echo
echo "\$ kubectl get deploy $REL-web -n $NS -o jsonpath='{.spec.template.spec.containers[0].image}{\"  replicas=\"}{.status.readyReplicas}{\"\\n\"}'"
kubectl get deploy "$REL"-web -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].image}{"  replicas="}{.status.readyReplicas}{"\n"}'
echo
echo "\$ kubectl get pods -n $NS -l app.kubernetes.io/instance=$REL -o custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image,PHASE:.status.phase"
kubectl get pods -n "$NS" -l app.kubernetes.io/instance="$REL" \
  -o custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image,PHASE:.status.phase
echo

# Port-forward to the Service on my assigned host port, curl it, then stop.
kubectl port-forward -n "$NS" svc/"$REL"-web "$PORT":80 >/dev/null 2>&1 &
PF=$!
trap 'kill $PF 2>/dev/null || true' EXIT
for _ in $(seq 1 20); do curl -s -o /dev/null "http://localhost:$PORT/" && break; sleep 0.5; done

echo "\$ curl -s http://localhost:$PORT/version.txt"
curl -s "http://localhost:$PORT/version.txt"
echo
echo "\$ curl -sI http://localhost:$PORT/ | grep Server"
curl -sI "http://localhost:$PORT/" | grep Server
