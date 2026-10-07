#!/usr/bin/env bash
# Prints a timestamped snapshot of the HPA, the pods and their CPU usage
# every INTERVAL seconds. Usage: ./watch-hpa.sh [namespace] [interval]
NS="${1:-s13-hpa}"
INTERVAL="${2:-20}"
while true; do
  echo "===== $(date '+%H:%M:%S') ====="
  kubectl get hpa -n "$NS" --no-headers
  kubectl get pods -n "$NS" -l app=hpa-demo --no-headers
  kubectl top pods -n "$NS" --no-headers 2>&1
  sleep "$INTERVAL"
done
