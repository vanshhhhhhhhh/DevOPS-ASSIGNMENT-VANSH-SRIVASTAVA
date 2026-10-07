#!/usr/bin/env bash
# Generates mixed traffic against s20-app with `hey` (brew install hey).
# Four streams run in parallel for DURATION:
#   /api/orders   ~20 req/s  normal traffic (about 2% fail)
#   /api/slow      ~3 req/s  0.5-1.5 s each, pushes p95 latency up
#   /api/error     ~3 req/s  always 500, pushes the error rate up
#   /api/cpu       ~8 req/s  each burns 100 ms of CPU, pushes CPU usage up
# Usage: ./load.sh [duration]   e.g. ./load.sh 120s
set -euo pipefail

DURATION="${1:-120s}"
BASE="${BASE_URL:-http://localhost:8300}"
OUT="$(mktemp -d)"

command -v hey >/dev/null || { echo "hey is not installed (brew install hey)"; exit 1; }
curl -fsS "$BASE/health" >/dev/null || { echo "app not reachable at $BASE"; exit 1; }

echo "load: $DURATION against $BASE (summaries in $OUT)"
hey -z "$DURATION" -c 4 -q 5 "$BASE/api/orders"      > "$OUT/orders.txt" &
hey -z "$DURATION" -c 3 -q 1 "$BASE/api/slow"        > "$OUT/slow.txt"   &
hey -z "$DURATION" -c 1 -q 3 "$BASE/api/error"       > "$OUT/error.txt"  &
hey -z "$DURATION" -c 2 -q 4 "$BASE/api/cpu?ms=100"  > "$OUT/cpu.txt"    &
wait

for f in orders slow error cpu; do
  echo "--- /api/$f"
  grep -E "Requests/sec|Average:|Slowest:" "$OUT/$f.txt"
  sed -n '/Status code distribution:/,/^$/p' "$OUT/$f.txt" | grep -E '\[[0-9]+\]'
done
