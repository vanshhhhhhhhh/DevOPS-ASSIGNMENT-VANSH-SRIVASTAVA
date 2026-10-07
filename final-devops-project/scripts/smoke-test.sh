#!/usr/bin/env bash
# End-to-end smoke test through the frontend (nginx -> backend -> PostgreSQL).
# Usage: scripts/smoke-test.sh http://localhost:8400 [Host-header]
# Used locally (docker compose, minikube port-forward, ingress) and in CI (kind).
set -euo pipefail

BASE_URL="${1:-http://localhost:8400}"
HOST_HEADER="${2:-}"
CURL=(curl -sS --fail --max-time 10)
if [[ -n "$HOST_HEADER" ]]; then CURL+=(-H "Host: ${HOST_HEADER}"); fi

step() { printf '\n--- %s\n' "$*"; }

step "GET / (frontend HTML)"
"${CURL[@]}" "$BASE_URL/" | grep -o '<title>[^<]*</title>'

step "GET /api/health"
"${CURL[@]}" "$BASE_URL/api/health"; echo

step "POST /api/tickets"
created=$("${CURL[@]}" -X POST "$BASE_URL/api/tickets" -H 'Content-Type: application/json' \
  -d '{"title":"Smoke test ticket","requester":"smoke@example.com","category":"TECHNICAL","priority":"HIGH","description":"created by scripts/smoke-test.sh"}')
echo "$created"
id=$(printf '%s' "$created" | sed -E 's/.*"id":([0-9]+).*/\1/')

step "PATCH /api/tickets/$id (status -> IN_PROGRESS)"
"${CURL[@]}" -X PATCH "$BASE_URL/api/tickets/$id" -H 'Content-Type: application/json' -d '{"status":"IN_PROGRESS"}' \
  | grep -o '"status":"[A-Z_]*"'

step "GET /api/tickets/stats"
"${CURL[@]}" "$BASE_URL/api/tickets/stats"; echo

step "DELETE /api/tickets/$id"
code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 ${HOST_HEADER:+-H "Host: ${HOST_HEADER}"} -X DELETE "$BASE_URL/api/tickets/$id")
echo "HTTP $code"
[[ "$code" == "204" ]]

printf '\nSMOKE TEST PASSED against %s\n' "$BASE_URL"
