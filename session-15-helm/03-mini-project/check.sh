#!/usr/bin/env bash
# Shows the state of the notes release: Helm history, running pods/images,
# the env vars from the ConfigMap, and what the app returns over HTTP.
# Usage: ./check.sh [namespace] [release] [local-port]
set -uo pipefail
NS=${1:-s15-notes}
REL=${2:-s15-notes-dev}
PORT=${3:-18320}

echo "\$ helm history $REL -n $NS"
helm history "$REL" -n "$NS" | column -t -s $'\t'
echo
echo "\$ kubectl get pods -n $NS -o custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image,READY:.status.containerStatuses[0].ready,STATE:.status.containerStatuses[0].state.waiting.reason"
kubectl get pods -n "$NS" -l app="$REL" \
  -o custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image,READY:.status.containerStatuses[0].ready,STATE:.status.containerStatuses[0].state.waiting.reason
echo
echo "\$ kubectl get configmap $REL-config -n $NS -o jsonpath='{.data}'"
kubectl get configmap "$REL"-config -n "$NS" -o jsonpath='{.data}'; echo
echo

# Port-forward to the Service on my assigned host port (picks a ready pod).
kubectl port-forward -n "$NS" svc/"$REL"-svc "$PORT":80 >/dev/null 2>&1 &
PF=$!
trap 'kill $PF 2>/dev/null || true' EXIT
for _ in $(seq 1 20); do curl -s -o /dev/null "http://localhost:$PORT/" && break; sleep 0.5; done

echo "\$ curl -s http://localhost:$PORT/ | grep -E '<h1>|environment|image|replicas'"
curl -s "http://localhost:$PORT/" | grep -E '<h1>|environment|image|replicas' | sed 's/^ *//'
echo
echo "\$ curl -sI http://localhost:$PORT/ | grep Server"
curl -sI "http://localhost:$PORT/" | grep Server
