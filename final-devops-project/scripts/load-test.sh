#!/usr/bin/env bash
# Generates traffic so the Grafana panels and the HPA have something to show.
# Usage: scripts/load-test.sh http://localhost:8420 [seconds] [concurrency]
# Needs "hey" (brew install hey).
set -euo pipefail
BASE_URL="${1:-http://localhost:8420}"
DURATION="${2:-60}"
CONCURRENCY="${3:-20}"
for i in 1 2 3 4 5; do
  curl -sS -o /dev/null -X POST "$BASE_URL/api/tickets" -H 'Content-Type: application/json' \
    -d "{\"title\":\"Load test ticket $i\",\"requester\":\"load@example.com\",\"priority\":\"URGENT\"}"
done
hey -z "${DURATION}s" -c "$CONCURRENCY" "$BASE_URL/api/tickets" | sed -n '1,20p'
