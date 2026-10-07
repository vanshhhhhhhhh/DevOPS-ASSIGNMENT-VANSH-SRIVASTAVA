#!/bin/sh
# Container entrypoint: apply database migrations, then start the API.
# The database may still be starting (in Kubernetes the headless Service name
# does not even resolve until the PostgreSQL pod is Ready), so migrations are
# retried for up to ~60s instead of crash-looping the container.
set -eu
if [ "${RUN_MIGRATIONS:-true}" = "true" ]; then
  attempt=1
  until alembic upgrade head; do
    if [ "$attempt" -ge "${MIGRATION_RETRIES:-30}" ]; then
      echo "database not reachable after $attempt attempts, giving up" >&2
      exit 1
    fi
    echo "migration attempt $attempt failed, retrying in 2s" >&2
    attempt=$((attempt + 1))
    sleep 2
  done
fi
exec uvicorn app.main:app --host 0.0.0.0 --port "${PORT:-8000}"
