#!/usr/bin/env bash
# Creates a few sample tickets so the UI and dashboards are not empty.
# Usage: scripts/seed-tickets.sh http://localhost:8400 [Host-header]
set -euo pipefail
BASE_URL="${1:-http://localhost:8400}"
H=(); [[ -n "${2:-}" ]] && H=(-H "Host: $2")
post() { curl -sS --fail ${H[@]+"${H[@]}"} -o /dev/null -X POST "$BASE_URL/api/tickets" -H 'Content-Type: application/json' -d "$1"; }
patch() { curl -sS --fail ${H[@]+"${H[@]}"} -o /dev/null -X PATCH "$BASE_URL/api/tickets/$1" -H 'Content-Type: application/json' -d "$2"; }
post '{"title":"VPN disconnects every 10 minutes","requester":"ravi@example.com","category":"TECHNICAL","priority":"HIGH","description":"Started after the client update on Monday."}'
post '{"title":"Invoice shows the wrong GST number","requester":"accounts@example.com","category":"BILLING","priority":"MEDIUM","description":"October invoice, customer id 4411."}'
post '{"title":"Cannot reset password","requester":"meera@example.com","category":"ACCOUNT","priority":"URGENT","description":"Reset mail never arrives, checked spam folder."}'
post '{"title":"Add dark mode to the portal","requester":"design@example.com","category":"GENERAL","priority":"LOW"}'
post '{"title":"Checkout page returns 502","requester":"oncall@example.com","category":"TECHNICAL","priority":"URGENT","description":"Seen in two regions since 09:40."}'
ids=$(curl -sS --fail ${H[@]+"${H[@]}"} "$BASE_URL/api/tickets" | grep -oE '"id":[0-9]+' | cut -d: -f2 | sort -n)
set -- $ids
patch "$1" '{"status":"IN_PROGRESS"}'
patch "$2" '{"status":"RESOLVED"}'
patch "$4" '{"status":"CLOSED"}'
echo "seeded: $(curl -sS --fail ${H[@]+"${H[@]}"} "$BASE_URL/api/tickets/stats")"
