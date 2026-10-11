# Session 21: Final DevOps Project & Troubleshooting

**Name:** Vansh Srivastava
**Enrollment No.:** 24bcs10567
**Session:** 21

For the final project I built **TicketDesk**, a small support-ticket tracker (FastAPI + PostgreSQL backend, Vite frontend served by nginx), and took it through the whole flow from the brief: Application -> Git -> GitHub -> CI pipeline -> build and test -> security scanning -> Docker image -> container registry -> Kubernetes -> Helm -> monitoring -> GitOps. Infrastructure is provisioned with Terraform against LocalStack, and the session ends with a troubleshooting challenge in which I planted six faults in a deployment and fixed them one by one with real cluster output.

I read the instructor's reference implementation (`session21-python`, the TaskBoard app in [Nency-Ravaliya/devops-heros](https://github.com/Nency-Ravaliya/devops-heros)) to see what is expected, then wrote my own application in a different domain. The DevOps layer follows the same architecture (FastAPI + Postgres + nginx frontend, Helm, Ingress, HPA, Prometheus/Grafana, Trivy, GHCR).

## Folder structure

```text
final-devops-project/
├── application/
│   ├── backend/                    # FastAPI app (app/), Alembic migration, pytest tests, start.sh entrypoint
│   └── frontend/                   # Vite + plain JavaScript UI, nginx config template (proxies /api)
├── docker/
│   ├── backend.Dockerfile          # multi-stage Python image, non-root uid 10001, no pip at runtime
│   ├── frontend.Dockerfile         # Node build stage -> nginx-unprivileged (uid 101, port 8080)
│   ├── docker-compose.yml          # postgres + backend + frontend on ports 8400/8401
│   └── .env.example
├── kubernetes/                     # plain manifests: namespace, ConfigMap, Secret, Postgres StatefulSet,
│                                   # backend/frontend Deployments + Services, Ingress, HPA
├── helm/ticketdesk/                # Helm chart (values.yaml, values-minikube.yaml, values-ci.yaml, helm test)
├── terraform/                      # VPC, subnets, IGW, route tables, security groups, S3, DynamoDB (LocalStack)
├── .github/workflows/ci-cd.yml     # copy of the pipeline; GitHub runs the root .github/workflows/final-project.yml
├── security/                       # gitleaks, bandit, trivy configs + README explaining each gate
├── monitoring/                     # Prometheus + Grafana Helm values (alert rules inside), Grafana dashboard JSON
├── gitops/argocd-application.yaml  # Argo CD Application for the Helm chart (automated sync)
├── troubleshooting/                # broken/ (6 planted faults) and fixed/ manifests
├── scripts/                        # smoke-test.sh, seed-tickets.sh, load-test.sh, screenshot-cdp.mjs
├── screenshots/                    # headless-Chrome captures used below
├── .semgrepignore
├── .gitignore
└── README.md
```

## Environment

```text
macOS (Apple Silicon, arm64), Docker 29.5.2 via Colima, Docker Compose v5
minikube v1.39.0, Kubernetes v1.37.0 (containerd), ingress-nginx + metrics-server addons
kubectl v1.37.1, Helm v4.3.0, Terraform v1.16.4, LocalStack 4.14.0 (shared container)
Python 3.12 (python:3.12-slim containers), Node 26 locally / Node 22 in the image and CI
```

Everything I created uses the `final-` prefix: namespaces `final-app`, `final-k8s`, `final-monitoring`, `final-troubleshoot`, Docker objects `final-ticketdesk-*`, Helm releases `final-*`, and host ports 8400-8450.

## Project overview

TicketDesk lets a small team open support tickets, move them through `OPEN -> IN_PROGRESS -> RESOLVED -> CLOSED`, filter them, and see counts per status and priority.

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/health` (also `/api/health`) | liveness: process is up, no DB access |
| GET | `/ready` | readiness: runs `SELECT 1`, returns 503 when the database is down |
| GET | `/metrics` | Prometheus metrics (HTTP metrics + business counters) |
| GET | `/api/tickets?status=&priority=` | list tickets, newest first, with filters |
| GET | `/api/tickets/{id}` | one ticket (404 if missing) |
| POST | `/api/tickets` | create (validated by Pydantic, 201) |
| PATCH | `/api/tickets/{id}` | partial update, e.g. status change |
| DELETE | `/api/tickets/{id}` | delete (204) |
| GET | `/api/tickets/stats` | counts by status and priority |
| GET | `/api/docs` | Swagger UI (under `/api` so it also works through nginx and the Ingress) |

Two custom metrics are exported: `ticketdesk_tickets_created_total{priority}` and `ticketdesk_ticket_status_changes_total{status}`.

## Architecture

```mermaid
flowchart LR
    dev[Developer] -->|git push| gh[GitHub repo]
    gh --> ci

    subgraph ci[GitHub Actions: final-project.yml]
        direction TB
        t[Build and test<br/>pytest + Postgres service<br/>vite build] --> img
        s1[SAST<br/>Bandit, Semgrep] --> img
        s2[SCA<br/>pip-audit, npm audit, Trivy fs] --> img
        s3[Secret scan<br/>gitleaks] --> img
        img[Docker build<br/>Trivy image gate] --> kind[Deploy to kind<br/>helm upgrade --install<br/>helm test + smoke test]
    end

    img -->|push sha tag, main only| ghcr[(GHCR<br/>ticketdesk-backend<br/>ticketdesk-frontend)]

    subgraph k8s[minikube cluster]
        direction TB
        ing[ingress-nginx<br/>ticketdesk.final.local] -->|/| fe[frontend x2<br/>nginx :8080]
        ing -->|/api| be[backend x2-5 HPA<br/>FastAPI :8000]
        fe -->|/api proxy| be
        be --> pg[(PostgreSQL<br/>StatefulSet + PVC)]
        prom[Prometheus] -->|scrape /metrics<br/>pod annotations| be
        graf[Grafana] --> prom
    end

    gh -->|watch main, helm chart| argo[Argo CD Application] -->|sync| k8s
    tf[Terraform] -->|VPC, subnets, SGs,<br/>S3 backups, DynamoDB lock| ls[(LocalStack AWS)]
```

## Technologies used

| Area | Tools |
|------|-------|
| Application | Python 3.12, FastAPI 0.142, SQLAlchemy 2.1, psycopg 3, Alembic 1.20, Pydantic settings, prometheus-fastapi-instrumentator; Vite 8 + plain JavaScript; nginx-unprivileged 1.29 |
| Testing | pytest 9, pytest-cov, FastAPI TestClient (httpx2), SQLite locally / PostgreSQL in CI |
| Containers | Docker multi-stage builds, Docker Compose |
| Kubernetes | minikube, Deployments, StatefulSet + PVC, Services, ConfigMap, Secret, Ingress (ingress-nginx), HPA (metrics-server), startup/liveness/readiness probes, securityContext |
| Packaging | Helm 4 chart with `helm test` |
| IaC | Terraform 1.16 + hashicorp/aws 6.67 against LocalStack 4.14 |
| CI/CD | GitHub Actions, GHCR, kind (helm/kind-action) |
| DevSecOps | Bandit, Semgrep, pip-audit, npm audit, Trivy (fs, image, config), gitleaks |
| Observability | Prometheus 3.15 (prometheus-community chart), Grafana 13.2 (grafana-community chart), alert rules |
| GitOps | Argo CD v3.5 Application |

## Task 1: Application setup

Code: `application/backend` (FastAPI) and `application/frontend` (Vite). The backend reads its configuration from environment variables: `DATABASE_URL`, or `DB_HOST/DB_PORT/DB_NAME/DB_USER/DB_PASSWORD` (Kubernetes passes the parts from a ConfigMap and the password from a Secret). The schema is managed by Alembic (`alembic/versions/0001_create_tickets.py`). `alembic/env.py` takes a PostgreSQL advisory lock before migrating, so two backend replicas starting at the same time do not both try to create the table. `start.sh` retries the migration for about 60 seconds before starting uvicorn (the reason is in Task 3).

Run it directly (API on 8401, UI dev server with `/api` proxied):

```bash
$ cd application/backend && python3.12 -m venv .venv && . .venv/bin/activate
$ pip install -r requirements-dev.txt
$ export DATABASE_URL=postgresql+psycopg://ticketdesk:demo-password-123@localhost:5432/ticketdesk
$ alembic upgrade head && uvicorn app.main:app --port 8401
$ cd ../frontend && npm ci && npm run dev      # http://localhost:5173
```

### Tests

15 tests in `tests/test_meta.py` and `tests/test_tickets.py` cover every endpoint, validation errors (422), 404s, the 503 readiness path (the DB session is replaced by one that raises `OperationalError`), the filters, the stats endpoint and the metrics output. `conftest.py` uses a throw-away SQLite file unless `DATABASE_URL` is set; CI sets it to a PostgreSQL service container. I ran both variants in `python:3.12-slim` containers (the Mac only has Python 3.9):

```bash
$ pytest -v --cov=app --cov-report=term-missing      # SQLite (no DATABASE_URL set)
============================= test session starts ==============================
platform linux -- Python 3.12.15, pytest-9.1.1, pluggy-1.6.0 -- /usr/local/bin/python
rootdir: /src
configfile: pytest.ini
testpaths: tests
plugins: cov-7.1.0, anyio-4.15.1
collecting ... collected 15 items

tests/test_meta.py::test_root_reports_service_name PASSED                [  6%]
tests/test_meta.py::test_health_is_ok_without_database PASSED            [ 13%]
tests/test_meta.py::test_ready_when_database_answers PASSED              [ 20%]
tests/test_meta.py::test_ready_returns_503_when_database_is_down PASSED  [ 26%]
tests/test_meta.py::test_openapi_docs_are_served_under_api_prefix PASSED [ 33%]
tests/test_meta.py::test_metrics_expose_http_and_business_counters PASSED [ 40%]
tests/test_tickets.py::test_create_ticket_returns_201_and_defaults PASSED [ 46%]
tests/test_tickets.py::test_create_ticket_rejects_short_title PASSED     [ 53%]
tests/test_tickets.py::test_create_ticket_rejects_unknown_priority PASSED [ 60%]
tests/test_tickets.py::test_list_tickets_newest_first_and_filters PASSED [ 66%]
tests/test_tickets.py::test_get_ticket_and_404 PASSED                    [ 73%]
tests/test_tickets.py::test_patch_updates_only_given_fields PASSED       [ 80%]
tests/test_tickets.py::test_patch_rejects_invalid_status_and_missing_ticket PASSED [ 86%]
tests/test_tickets.py::test_delete_ticket PASSED                         [ 93%]
tests/test_tickets.py::test_stats_counts_by_status_and_priority PASSED   [100%]

================================ tests coverage ================================
_______________ coverage: platform linux, python 3.12.15-final-0 _______________

Name              Stmts   Miss  Cover   Missing
-----------------------------------------------
app/__init__.py       0      0   100%
app/config.py        24      1    96%   34
app/db.py            13      0   100%
app/main.py          83      0   100%
app/models.py        17      0   100%
app/schemas.py       33      0   100%
-----------------------------------------------
TOTAL               170      1    99%
============================== 15 passed in 0.26s ==============================
exit code: 0
```

The same suite against a PostgreSQL 17 container, the way the CI job runs it (migrate first, then test):

```bash
$ export DATABASE_URL=postgresql+psycopg://ticketdesk:***@final-pytest-pg:5432/ticketdesk_test   # throw-away password masked
$ alembic upgrade head
INFO  [alembic.runtime.migration] Context impl PostgresqlImpl.
INFO  [alembic.runtime.migration] Will assume transactional DDL.
INFO  [alembic.runtime.migration] Running upgrade  -> 0001_create_tickets, create tickets table
$ pytest -q --cov=app --junitxml=/tmp/junit.xml
...............                                                          [100%]
...
TOTAL               170      1    99%
15 passed in 0.28s
exit code: 0
```

### Frontend build

```bash
$ npm run build

> ticketdesk-frontend@1.0.0 build
> vite build

vite v8.3.3 building client environment for production...
transforming...
✓ 6 modules transformed.
rendering chunks...
computing gzip size...
dist/index.html                 2.57 kB │ gzip: 1.03 kB
dist/assets/index-Db1qWLER.css  4.07 kB │ gzip: 1.35 kB
dist/assets/index-22vRT8Q4.js   3.98 kB │ gzip: 1.81 kB

✓ built in 48ms
```

The UI renders all user text with `textContent` (never `innerHTML`), so ticket content cannot inject markup.

## Task 2: Docker setup

- `docker/backend.Dockerfile`: build stage creates a virtualenv with the pinned requirements; the runtime stage runs `apt-get upgrade`, removes `pip` (not needed at runtime), creates user `app` (uid 10001), copies only `app/`, `alembic/`, `alembic.ini`, `start.sh`, and has a `HEALTHCHECK` on `/health`.
- `docker/frontend.Dockerfile`: `node:22-alpine` builds the static site, `nginx-unprivileged:1.29-alpine` serves it as uid 101 on port 8080. `apk upgrade` pulls Alpine security fixes newer than the base image. nginx's entrypoint renders `nginx/default.conf.template`, so the `/api/` proxy target comes from `BACKEND_URL` (compose: `http://backend:8000`, Kubernetes: the backend Service).
- Base images come from `public.ecr.aws/docker/library/...` (the ECR Public mirror of the Docker official images). Docker Hub refused anonymous pulls on this machine:

```bash
$ docker pull python:3.12-slim
Error response from daemon: unknown: failed to resolve reference "docker.io/library/python:3.12-slim": unexpected status from HEAD request to https://registry-1.docker.io/v2/library/python/manifests/3.12-slim: 429 Too Many Requests
```

Clean rebuild (no cache, fresh base images) and start:

```bash
$ cd docker
$ docker compose build --pull --no-cache
...
#27 2.497 ( 1/20) Upgrading alpine-release (3.23.4-r0 -> 3.23.6-r0)
#27 2.531 ( 2/20) Upgrading libcrypto3 (3.5.6-r0 -> 3.5.9-r0)
#27 2.851 ( 3/20) Upgrading libssl3 (3.5.6-r0 -> 3.5.9-r0)
...
#27 3.146 ( 8/20) Upgrading libcurl (8.17.0-r1 -> 8.22.0-r0)
#27 3.223 ( 9/20) Upgrading curl (8.17.0-r1 -> 8.22.0-r0)
#27 3.336 (10/20) Upgrading pcre2 (10.47-r0 -> 10.49-r0)
...
#21 3.329 1 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
 Image ticketdesk-backend:1.0.0 Built 
 Image ticketdesk-frontend:1.0.0 Built 
$ docker compose up -d
...
 Container final-ticketdesk-postgres Healthy 
 Container final-ticketdesk-backend Starting 
 Container final-ticketdesk-backend Started 
 Container final-ticketdesk-backend Waiting 
 Container final-ticketdesk-backend Healthy 
 Container final-ticketdesk-frontend Starting 
 Container final-ticketdesk-frontend Started
$ docker compose ps
NAME                        IMAGE                                              STATUS                    PORTS
final-ticketdesk-backend    ticketdesk-backend:1.0.0                           Up 12 seconds (healthy)   127.0.0.1:8401->8000/tcp
final-ticketdesk-frontend   ticketdesk-frontend:1.0.0                          Up 6 seconds (healthy)    127.0.0.1:8400->8080/tcp
final-ticketdesk-postgres   public.ecr.aws/docker/library/postgres:17-alpine   Up 18 seconds (healthy)   5432/tcp
$ docker image ls ticketdesk-*
REPOSITORY                                        TAG                SIZE
ticketdesk-backend                                1.0.0              308MB
ticketdesk-frontend                               1.0.0              112MB
```

`depends_on: condition: service_healthy` makes the backend wait for `pg_isready` and the frontend wait for the backend's own healthcheck. On the very first start (empty volume) the backend log showed the migration and then uvicorn:

```bash
$ docker compose logs backend | head -12
INFO  [alembic.runtime.migration] Context impl PostgresqlImpl.
INFO  [alembic.runtime.migration] Will assume transactional DDL.
INFO  [alembic.runtime.migration] Running upgrade  -> 0001_create_tickets, create tickets table
INFO:     Started server process [1]
INFO:     Waiting for application startup.
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
INFO:     127.0.0.1:37784 - "GET /health HTTP/1.1" 200 OK
```

End-to-end smoke test through nginx -> backend -> PostgreSQL (`scripts/smoke-test.sh`):

```bash
$ scripts/smoke-test.sh http://localhost:8400

--- GET / (frontend HTML)
<title>TicketDesk</title>

--- GET /api/health
{"status":"ok"}

--- POST /api/tickets
{"id":7,"title":"Smoke test ticket","description":"created by scripts/smoke-test.sh","requester":"smoke@example.com","category":"TECHNICAL","priority":"HIGH","status":"OPEN","created_at":"2026-10-11T20:13:27.568530Z","updated_at":"2026-10-11T20:13:27.568535Z"}

--- PATCH /api/tickets/7 (status -> IN_PROGRESS)
"status":"IN_PROGRESS"

--- GET /api/tickets/stats
{"total":6,"by_status":{"OPEN":2,"IN_PROGRESS":2,"RESOLVED":1,"CLOSED":1},"by_priority":{"LOW":1,"MEDIUM":1,"HIGH":2,"URGENT":2}}

--- DELETE /api/tickets/7
HTTP 204

SMOKE TEST PASSED against http://localhost:8400
```

Backend probes and metrics, straight on the backend port:

```bash
$ curl -s localhost:8401/health; curl -s localhost:8401/ready
{"status":"ok"}
{"status":"ready","database":"up"}
$ curl -s localhost:8401/metrics | grep -E "^(ticketdesk_|http_requests_total)" | head
ticketdesk_tickets_created_total{priority="HIGH"} 1.0
ticketdesk_tickets_created_created{priority="HIGH"} 1.7913957427150073e+09
ticketdesk_ticket_status_changes_total{status="IN_PROGRESS"} 1.0
ticketdesk_ticket_status_changes_created{status="IN_PROGRESS"} 1.7913957427367184e+09
http_requests_total{handler="/health",method="GET",status="2xx"} 4.0
http_requests_total{handler="/api/health",method="GET",status="2xx"} 1.0
http_requests_total{handler="/api/tickets",method="POST",status="2xx"} 1.0
http_requests_total{handler="/api/tickets/{ticket_id}",method="PATCH",status="2xx"} 1.0
http_requests_total{handler="/api/tickets/stats",method="GET",status="2xx"} 1.0
http_requests_total{handler="/api/tickets/{ticket_id}",method="DELETE",status="2xx"} 1.0
```

![TicketDesk UI served by docker compose](screenshots/01-app-ui-compose.png)

![Swagger UI at /api/docs](screenshots/02-api-docs-swagger.png)

## Task 3: Kubernetes deployment (plain manifests)

`kubernetes/` deploys the full stack into namespace `final-k8s`:

| File | Objects | Notes |
|------|---------|-------|
| `00-namespace.yaml` | Namespace | |
| `01-configmap.yaml` | ConfigMap | DB host/port/name/user, log level |
| `02-secret.yaml` | Secret | `DB_PASSWORD` (demo value; real setups use External Secrets / Sealed Secrets) |
| `10-postgres.yaml` | headless Service + StatefulSet | `volumeClaimTemplates` 1Gi PVC, `pg_isready` probes, runs as uid 70, read-only root FS |
| `20-backend.yaml` | Deployment + Service | startup/liveness probes on `/health`, readiness on `/ready`, requests 50m/128Mi, uid 10001, read-only root FS, `prometheus.io/*` annotations; no `replicas` because the HPA owns it |
| `30-frontend.yaml` | Deployment (2 replicas) + Service | probes on `/healthz`, uid 101, read-only root FS with emptyDirs for `/tmp` and `conf.d` |
| `50-ingress.yaml` | Ingress | host `ticketdesk-k8s.final.local`: `/api` -> backend, `/` -> frontend |
| `60-hpa.yaml` | HPA (autoscaling/v2) | backend 2-5 replicas, CPU 70% / memory 80% of requests |

The images are local, so I loaded them into minikube first (`minikube image load ticketdesk-backend:1.0.0`, same for the frontend and `postgres:17-alpine`).

**First attempt.** All pods came up, but both backend pods had restarted twice:

```bash
$ kubectl -n final-k8s get pods
NAME                                   READY   STATUS    RESTARTS      AGE
ticketdesk-backend-8579db5ddb-dfwcn    1/1     Running   2 (17s ago)   21s
ticketdesk-backend-8579db5ddb-vml7r    1/1     Running   2 (17s ago)   21s
ticketdesk-frontend-6d54b6969c-hd75s   1/1     Running   0             21s
ticketdesk-frontend-6d54b6969c-j9tpx   1/1     Running   0             21s
ticketdesk-postgres-0                  1/1     Running   0             21s
$ kubectl -n final-k8s logs deploy/ticketdesk-backend --previous | tail -5
               ^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/opt/venv/lib/python3.12/site-packages/psycopg/_conninfo_attempts.py", line 55, in conninfo_attempts
    raise last_exc
sqlalchemy.exc.OperationalError: (psycopg.OperationalError) failed to resolve host 'ticketdesk-postgres': [Errno -2] Name or service not known
(Background on this error at: https://sqlalche.me/e/21/e3q8)
```

A headless Service has no ClusterIP, so its DNS name does not resolve at all until the PostgreSQL pod is Ready. `alembic upgrade head` failed, the container exited and Kubernetes restarted it. I changed `start.sh` to retry the migration (up to 30 times, 2 s apart) instead of crash-looping, rebuilt the image and redeployed from scratch:

```bash
$ kubectl apply -f kubernetes/
namespace/final-k8s created
configmap/ticketdesk-config created
secret/ticketdesk-db created
service/ticketdesk-postgres created
statefulset.apps/ticketdesk-postgres created
deployment.apps/ticketdesk-backend created
service/ticketdesk-backend created
deployment.apps/ticketdesk-frontend created
service/ticketdesk-frontend created
ingress.networking.k8s.io/ticketdesk created
horizontalpodautoscaler.autoscaling/ticketdesk-backend created
$ kubectl -n final-k8s rollout status deploy/ticketdesk-backend
Waiting for deployment "ticketdesk-backend" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "ticketdesk-backend" rollout to finish: 0 of 2 updated replicas are available...
Waiting for deployment "ticketdesk-backend" rollout to finish: 1 of 2 updated replicas are available...
deployment "ticketdesk-backend" successfully rolled out
$ kubectl -n final-k8s get all,ingress,hpa,pvc,configmap,secret
NAME                                       READY   STATUS    RESTARTS   AGE
pod/ticketdesk-backend-8579db5ddb-2mlpb    1/1     Running   0          29s
pod/ticketdesk-backend-8579db5ddb-wqvkp    1/1     Running   0          29s
pod/ticketdesk-frontend-6d54b6969c-2xl4w   1/1     Running   0          29s
pod/ticketdesk-frontend-6d54b6969c-gcl2v   1/1     Running   0          29s
pod/ticketdesk-postgres-0                  1/1     Running   0          29s

NAME                          TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/ticketdesk-backend    ClusterIP   10.101.203.2    <none>        8000/TCP   29s
service/ticketdesk-frontend   ClusterIP   10.105.126.62   <none>        80/TCP     29s
service/ticketdesk-postgres   ClusterIP   None            <none>        5432/TCP   29s

NAME                                  READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/ticketdesk-backend    2/2     2            2           29s
deployment.apps/ticketdesk-frontend   2/2     2            2           29s
...
NAME                                   READY   AGE
statefulset.apps/ticketdesk-postgres   1/1     29s

NAME                                                     REFERENCE                       TARGETS                                     MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/ticketdesk-backend   Deployment/ticketdesk-backend   cpu: <unknown>/70%, memory: <unknown>/80%   2         5         2          29s

NAME                                   CLASS   HOSTS                        ADDRESS        PORTS   AGE
ingress.networking.k8s.io/ticketdesk   nginx   ticketdesk-k8s.final.local   192.168.49.2   80      29s

NAME                                               STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/data-ticketdesk-postgres-0   Bound    pvc-5c695824-2311-4f44-982c-f24786639bf7   1Gi        RWO            standard       <unset>                 29s

NAME                          DATA   AGE
configmap/kube-root-ca.crt    1      29s
configmap/ticketdesk-config   6      29s

NAME                   TYPE     DATA   AGE
secret/ticketdesk-db   Opaque   1      29s
```

Zero restarts this time. The logs show both replicas retrying while Postgres started, and only one of them running the migration (the other waited on the advisory lock and then found nothing to do):

```bash
$ kubectl -n final-k8s logs <backend-pod> | grep -E "OperationalError|migration attempt|Running upgrade|Uvicorn running"
# pod/ticketdesk-backend-8579db5ddb-2mlpb
sqlalchemy.exc.OperationalError: (psycopg.OperationalError) failed to resolve host 'ticketdesk-postgres': [Errno -2] Name or service not known
migration attempt 1 failed, retrying in 2s
sqlalchemy.exc.OperationalError: (psycopg.OperationalError) failed to resolve host 'ticketdesk-postgres': [Errno -2] Name or service not known
migration attempt 2 failed, retrying in 2s
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
# pod/ticketdesk-backend-8579db5ddb-wqvkp
sqlalchemy.exc.OperationalError: (psycopg.OperationalError) failed to resolve host 'ticketdesk-postgres': [Errno -2] Name or service not known
migration attempt 1 failed, retrying in 2s
sqlalchemy.exc.OperationalError: (psycopg.OperationalError) failed to resolve host 'ticketdesk-postgres': [Errno -2] Name or service not known
migration attempt 2 failed, retrying in 2s
INFO  [alembic.runtime.migration] Running upgrade  -> 0001_create_tickets, create tickets table
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
```

**Ingress.** The minikube node IP is not reachable from the Mac, so I port-forwarded the shared ingress-nginx controller (without changing it) and sent the Host header:

```bash
$ kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8430:80 &
$ scripts/smoke-test.sh http://localhost:8430 ticketdesk-k8s.final.local

--- GET / (frontend HTML)
<title>TicketDesk</title>

--- GET /api/health
{"status":"ok"}

--- POST /api/tickets
{"id":1,"title":"Smoke test ticket","description":"created by scripts/smoke-test.sh","requester":"smoke@example.com","category":"TECHNICAL","priority":"HIGH","status":"OPEN","created_at":"2026-10-07T18:08:06.281444Z","updated_at":"2026-10-07T18:08:06.281451Z"}

--- PATCH /api/tickets/1 (status -> IN_PROGRESS)
"status":"IN_PROGRESS"

--- GET /api/tickets/stats
{"total":1,"by_status":{"OPEN":0,"IN_PROGRESS":1,"RESOLVED":0,"CLOSED":0},"by_priority":{"LOW":0,"MEDIUM":0,"HIGH":1,"URGENT":0}}

--- DELETE /api/tickets/1
HTTP 204

SMOKE TEST PASSED against http://localhost:8430
```

**HPA with metrics** (metrics-server needs about a minute before the targets stop being `<unknown>`):

```bash
$ kubectl -n final-k8s get hpa
NAME                 REFERENCE                       TARGETS                        MINPODS   MAXPODS   REPLICAS   AGE
ticketdesk-backend   Deployment/ticketdesk-backend   cpu: 6%/70%, memory: 49%/80%   2         5         2          96s
$ kubectl -n final-k8s top pods
NAME                                   CPU(cores)   MEMORY(bytes)   
ticketdesk-backend-8579db5ddb-2mlpb    3m           63Mi            
ticketdesk-backend-8579db5ddb-wqvkp    3m           63Mi            
ticketdesk-frontend-6d54b6969c-2xl4w   1m           5Mi             
ticketdesk-frontend-6d54b6969c-gcl2v   1m           5Mi             
ticketdesk-postgres-0                  6m           30Mi            
```

I set the backend memory request to 128Mi after seeing about 68 MiB in `docker stats`; with 96Mi the memory target of 80% would have been almost reached at idle.

**Storage.** A ticket survives deleting the database pod, because the StatefulSet reattaches the same PVC:

```bash
$ curl -s -X POST -H "Host: ticketdesk-k8s.final.local" localhost:8430/api/tickets -d {"title":"Survives a pod restart",...}
{"id":2,"title":"Survives a pod restart","description":"","requester":"pvc@examp
$ kubectl -n final-k8s delete pod ticketdesk-postgres-0
pod "ticketdesk-postgres-0" deleted from final-k8s namespace
$ kubectl -n final-k8s wait --for=condition=Ready pod/ticketdesk-postgres-0 --timeout=120s
pod/ticketdesk-postgres-0 condition met
$ curl -s -H "Host: ticketdesk-k8s.final.local" localhost:8430/api/tickets
[{"id":2,"title":"Survives a pod restart","description":"","requester":"pvc@example.com","category":"GENERAL","priority"
```

I deleted `final-k8s` afterwards to free memory; the Helm release below is the one I kept running. Later a Semgrep finding made me add `readOnlyRootFilesystem` and a `/tmp` emptyDir to the Postgres container in both the manifest and the chart; I checked first that `postgres:17-alpine` initialises a new database with a read-only root (`docker run --read-only --tmpfs /tmp --tmpfs /var/run/postgresql ...` reached "database system is ready to accept connections"), and then verified it live through the Helm upgrade in Task 4.

## Task 4: Helm deployment

`helm/ticketdesk` packages the same objects with values for images, replicas, resources, autoscaling, Postgres, Ingress and metrics. Notable choices:

- Object names come from the release (`final-ticketdesk-backend`, ...); selector labels are `app.kubernetes.io/name|instance|component`.
- `checksum/config` and `checksum/secret` pod annotations roll the pods when the ConfigMap or Secret changes.
- `postgres.existingSecret` lets a real environment provide the password out-of-band.
- Optional `ServiceMonitor` and `PrometheusRule` templates for clusters with the Prometheus Operator (off by default, because this project scrapes by pod annotations).
- `templates/tests/test-api.yaml` is a `helm test` pod that calls the API through the frontend Service, using the backend image (it already has Python, so no extra image is pulled).
- `values-minikube.yaml` (local images, host `ticketdesk.final.local`) and `values-ci.yaml` (kind, `pullPolicy: Never`, HPA off because kind has no metrics-server).

```bash
$ helm lint helm/ticketdesk -f helm/ticketdesk/values-minikube.yaml
==> Linting helm/ticketdesk
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed
$ helm upgrade --install final-ticketdesk helm/ticketdesk -n final-app --create-namespace -f helm/ticketdesk/values-minikube.yaml --wait --timeout 5m
Release "final-ticketdesk" does not exist. Installing it now.
NAME: final-ticketdesk
LAST DEPLOYED: Wed Oct  7 23:41:04 2026
NAMESPACE: final-app
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
NOTES:
TicketDesk 1.0.0 is deployed as release "final-ticketdesk" in namespace "final-app".

Backend image:  ticketdesk-backend:1.0.0
Frontend image: ticketdesk-frontend:1.0.0

Open the UI with a port-forward:
  kubectl -n final-app port-forward svc/final-ticketdesk-frontend 8420:80
  open http://localhost:8420   (API docs: http://localhost:8420/api/docs)

Through the Ingress (nginx): http://ticketdesk.final.local/

Run the chart's smoke test:
  helm test final-ticketdesk -n final-app
$ kubectl -n final-app get pods,svc,ingress,hpa,pvc
NAME                                             READY   STATUS    RESTARTS   AGE
pod/final-ticketdesk-backend-5f6745ddfd-hrqfk    1/1     Running   0          13s
pod/final-ticketdesk-backend-5f6745ddfd-lctb6    1/1     Running   0          13s
pod/final-ticketdesk-frontend-75485855b6-mf26h   1/1     Running   0          13s
pod/final-ticketdesk-frontend-75485855b6-qrp25   1/1     Running   0          13s
pod/final-ticketdesk-postgres-0                  1/1     Running   0          13s

NAME                                TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/final-ticketdesk-backend    ClusterIP   10.101.135.41   <none>        8000/TCP   13s
service/final-ticketdesk-frontend   ClusterIP   10.102.58.196   <none>        80/TCP     13s
service/final-ticketdesk-postgres   ClusterIP   None            <none>        5432/TCP   13s

NAME                                         CLASS   HOSTS                    ADDRESS   PORTS   AGE
ingress.networking.k8s.io/final-ticketdesk   nginx   ticketdesk.final.local             80      13s

NAME                                                           REFERENCE                             TARGETS                                     MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/final-ticketdesk-backend   Deployment/final-ticketdesk-backend   cpu: <unknown>/70%, memory: <unknown>/80%   2         5         1          13s

NAME                                                     STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/data-final-ticketdesk-postgres-0   Bound    pvc-afbea3e9-e584-4ae3-80c8-4218d32f3e0b   1Gi        RWO            standard       <unset>                 13s
$ helm test final-ticketdesk -n final-app --logs
...
TEST SUITE:     final-ticketdesk-test-api
Last Started:   Wed Oct  7 23:41:17 2026
Last Completed: Wed Oct  7 23:41:21 2026
Phase:          Succeeded

POD LOGS: final-ticketdesk-test-api (test)
/api/health 200 {'status': 'ok'}
/api/tickets/stats 200 {'total': 0, 'by_status': {'OPEN': 0, 'IN_PROGRESS': 0, 'RESOLVED': 0, 'CLOSED': 0}, 'by_priority': {'LOW': 0, 'MEDIUM': 0, 'HIGH': 0, 'URGENT': 0}}
helm test passed
$ scripts/smoke-test.sh http://localhost:8430 ticketdesk.final.local
...
--- DELETE /api/tickets/1
HTTP 204

SMOKE TEST PASSED against http://localhost:8430
```

(`REPLICAS 1` on the HPA was a snapshot right after creation: the Deployment has no `replicas` field, starts at 1, and the HPA raised it to its minimum of 2 within seconds, which is why two backend pods are already listed.)

Upgrade to revision 2 after the Postgres read-only-root change and the rebuilt images; the PostgreSQL pod restarted on its PVC and the data (22 tickets) was still there:

```bash
$ helm upgrade --install final-ticketdesk helm/ticketdesk -n final-app -f helm/ticketdesk/values-minikube.yaml --wait --timeout 5m
Release "final-ticketdesk" has been upgraded. Happy Helming!
NAME: final-ticketdesk
LAST DEPLOYED: Mon Oct 12 01:45:53 2026
NAMESPACE: final-app
STATUS: deployed
REVISION: 2
DESCRIPTION: Upgrade complete
...
$ helm list -n final-app
NAME            	NAMESPACE	REVISION	UPDATED                             	STATUS  	CHART           	APP VERSION
final-ticketdesk	final-app	2       	2026-10-12 01:45:53.185556 +0530 IST	deployed	ticketdesk-0.1.0	1.0.0      
$ helm test final-ticketdesk -n final-app --logs
TEST SUITE:     final-ticketdesk-test-api
Last Started:   Mon Oct 12 01:46:15 2026
Last Completed: Mon Oct 12 01:46:20 2026
Phase:          Succeeded

POD LOGS: final-ticketdesk-test-api (test)
/api/health 200 {'status': 'ok'}
/api/tickets/stats 200 {'total': 22, 'by_status': {'OPEN': 19, 'IN_PROGRESS': 1, 'RESOLVED': 1, 'CLOSED': 1}, 'by_priority': {'LOW': 1, 'MEDIUM': 1, 'HIGH': 1, 'URGENT': 19}}
helm test passed
```

![TicketDesk through the Ingress (ticketdesk.final.local)](screenshots/03-app-ui-k8s-ingress.png)

The screenshot was taken through the ingress-nginx port-forward, with Chrome's `--host-resolver-rules="MAP ticketdesk.final.local 127.0.0.1"` so the browser sent the right Host header.

## Task 5: Terraform infrastructure

`terraform/` provisions the cloud side of the project against **LocalStack** (no AWS account is used). The provider uses fake `test` credentials, every service endpoint points at `http://localhost:4566`, and S3 uses path-style URLs, the same approach as sessions 18/19.

| File | Resources |
|------|-----------|
| `network.tf` | VPC 10.42.0.0/16, 2 public + 2 private subnets in ap-south-1a/1b, internet gateway, public and private route tables + associations |
| `security-groups.tf` | `web` (80/443 from anywhere), `app` (8000-8080 from `web` only), `db` (5432 from `app` only); egress limited to HTTPS + VPC CIDR |
| `storage.tf` | S3 bucket for DB backups/CI artifacts: versioning, SSE (AES256, bucket key), public access block, lifecycle (expire old versions after 30 days), TLS-only bucket policy; DynamoDB table `final-ticketdesk-tf-locks` for state locking |
| `outputs.tf` | VPC, subnet and SG IDs, bucket and lock-table names |
| `terraform.tfvars.example`, `backend-s3.tf.example` | example variables; how state would move to the S3 bucket + DynamoDB lock on real AWS |

`.terraform.lock.hcl` is committed (hashes for darwin_arm64, linux_amd64 and linux_arm64); state files are git-ignored.

```bash
$ terraform init
Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 6.0"...
- Installing hashicorp/aws v6.67.0...
- Installed hashicorp/aws v6.67.0 (signed by HashiCorp)
...
Terraform has been successfully initialized!
...
$ terraform validate
Success! The configuration is valid.
$ terraform plan -out=tfplan
...
Plan: 31 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + backup_bucket      = "final-ticketdesk-backups-24bcs10567"
  + private_subnet_ids = [
      + (known after apply),
      + (known after apply),
    ]
  + public_subnet_ids  = [
      + (known after apply),
      + (known after apply),
    ]
  + security_group_ids = {
      + app = (known after apply)
      + db  = (known after apply)
      + web = (known after apply)
    }
  + tf_lock_table      = "final-ticketdesk-tf-locks"
  + vpc_id             = (known after apply)
...
Saved the plan to: tfplan
```

The first apply created the network, security groups and DynamoDB table but failed on the bucket:

```bash
$ terraform apply tfplan
...
aws_dynamodb_table.tf_locks: Creation complete after 7s [id=final-ticketdesk-tf-locks]

Error: creating S3 Bucket (final-ticketdesk-backups-24bcs10567): operation error S3: CreateBucket, https response error StatusCode: 400, RequestID: abfdc63b-33eb-4b57-a143-f7ea85bb6181, HostID: s9lzHYrFp76ZVxRcpX9+5cjAnEH2ROuNkd2BHfIa6UkFVdtjf5mKR3/eTPFvsiP/XV/VLi31234=, api error InvalidTag: The TagValue you have provided is invalid

  with aws_s3_bucket.backups,
  on storage.tf line 5, in resource "aws_s3_bucket" "backups":
   5: resource "aws_s3_bucket" "backups" {
```

My `default_tags` had `Owner = "Vansh Srivastava (24bcs10567)"`, and S3 tag values may not contain parentheses (EC2 and DynamoDB accepted it). I changed it to `vansh-srivastava-24bcs10567`. Because the earlier resources were already in the state, the next plan only created the missing S3 resources and updated the tag on the rest:

```bash
$ terraform plan -out=tfplan
...
Plan: 6 to add, 21 to change, 0 to destroy.
$ terraform apply tfplan
...
aws_s3_bucket_lifecycle_configuration.backups: Creation complete after 56s [id=final-ticketdesk-backups-24bcs10567]

Apply complete! Resources: 6 added, 21 changed, 0 destroyed.

Outputs:

backup_bucket = "final-ticketdesk-backups-24bcs10567"
private_subnet_ids = [
  "subnet-667c5d70fb1e0676a",
  "subnet-828a33258abaddcc7",
]
public_subnet_ids = [
  "subnet-cb0ddcc255d84576d",
  "subnet-57f95b637f9df667f",
]
security_group_ids = {
  "app" = "sg-d91d6b1b6b2802a91"
  "db" = "sg-e1d7fe7b242dc7cf4"
  "web" = "sg-3cd2698a365c7536a"
}
tf_lock_table = "final-ticketdesk-tf-locks"
vpc_id = "vpc-1e2173c2bcb51a381"
```

Checking the result with the AWS CLI (the `public.ecr.aws/aws-cli/aws-cli` image, sharing the LocalStack container's network) and confirming the configuration is in sync (`-detailed-exitcode` returns 0 when there are no changes, 2 when there are):

```bash
$ terraform state list | wc -l
      32
$ aws ec2 describe-subnets --filters Name=vpc-id,Values=<vpc_id> --query "Subnets[].[CidrBlock,AvailabilityZone,Tags[?Key==\`Tier\`]|[0].Value]" --output text
10.42.11.0/24	ap-south-1a	private
10.42.1.0/24	ap-south-1a	public
10.42.2.0/24	ap-south-1b	public
10.42.12.0/24	ap-south-1b	private
$ aws s3api get-bucket-versioning --bucket final-ticketdesk-backups-24bcs10567
{
    "Status": "Enabled"
}
$ aws s3api get-bucket-encryption --bucket final-ticketdesk-backups-24bcs10567 --query ServerSideEncryptionConfiguration.Rules[0]
{
    "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
    },
    "BucketKeyEnabled": true
}
$ aws s3api get-public-access-block --bucket final-ticketdesk-backups-24bcs10567 --output text
PUBLICACCESSBLOCKCONFIGURATION	True	True	True	True
$ aws dynamodb describe-table --table-name final-ticketdesk-tf-locks --query "Table.[TableName,TableStatus,KeySchema[0].AttributeName,BillingModeSummary.BillingMode]" --output text
final-ticketdesk-tf-locks	ACTIVE	LockID	PAY_PER_REQUEST
$ terraform plan -detailed-exitcode
...
exit code: 0
$ terraform output -json security_group_ids
{"app":"sg-d91d6b1b6b2802a91","db":"sg-e1d7fe7b242dc7cf4","web":"sg-3cd2698a365c7536a"}
$ terraform destroy -auto-approve
...
aws_s3_bucket.backups: Destroying... [id=final-ticketdesk-backups-24bcs10567]
aws_s3_bucket.backups: Destruction complete after 0s
aws_dynamodb_table.tf_locks: Destruction complete after 0s
aws_route_table.private: Destruction complete after 0s
aws_route_table.public: Destruction complete after 0s
aws_internet_gateway.main: Destroying... [id=igw-4354bbfc79beb7e3e]
aws_internet_gateway.main: Destruction complete after 0s
aws_vpc.main: Destroying... [id=vpc-1e2173c2bcb51a381]
aws_vpc.main: Destruction complete after 0s

Destroy complete! Resources: 31 destroyed.
```

(31 resources plus 1 data source = the 32 entries in the state list.) The Kubernetes side of this project runs on minikube, so the VPC is the network a real EKS/RDS deployment would use; EKS itself is not available in LocalStack's free edition.

## Task 6: CI/CD pipeline

GitHub only runs workflows from the repository root, so **`.github/workflows/final-project.yml` at the repo root is the file GitHub executes**. `final-devops-project/.github/workflows/ci-cd.yml` is an identical copy kept with the project.

Triggers: push and pull request to `main` when `final-devops-project/**` or the workflow file changes, plus `workflow_dispatch`. Every `run` step uses `working-directory: final-devops-project`.

| Job | What it does | Gate |
|-----|--------------|------|
| `build-test` | PostgreSQL 17 service container, `alembic upgrade head`, `pytest` with coverage (JUnit + coverage XML uploaded), `npm ci && npm run build` (dist uploaded) | tests must pass |
| `sast` | Bandit (JSON report + gate), Semgrep (python/javascript/dockerfile/kubernetes rules), Trivy IaC config scan (report only) | Bandit medium+, any Semgrep finding |
| `sca` | pip-audit, npm audit, Trivy fs (lock files incl. dev deps + secrets) | any known vuln / high+ npm advisory / fixable HIGH+CRITICAL |
| `secret-scan` | gitleaks `dir` on `final-devops-project` only | any leak |
| `image` (needs all four) | builds both images tagged with the commit SHA, Trivy JSON reports, Trivy gate, uploads reports and a `docker save` tarball; on push to `main` only: log in to GHCR with `GITHUB_TOKEN` (`packages: write`) and push `ghcr.io/<owner>/ticketdesk-backend:<sha>` and `ticketdesk-frontend:<sha>` | fixable HIGH/CRITICAL |
| `deploy-kind` | creates an ephemeral kind cluster (`helm/kind-action`), `kind load docker-image` of the scanned images, `helm lint`, `helm upgrade --install ... --wait`, `kubectl rollout status`, `helm test`, port-forward + `scripts/smoke-test.sh`; dumps pods/logs/events on failure | rollout, helm test and smoke test must pass |

Action versions were checked against the latest releases with `gh api repos/<owner>/<repo>/releases/latest --jq .tag_name`:

```text
actions/checkout	v7.0.1
actions/setup-python	v7.0.0
actions/setup-node	v7.0.0
actions/upload-artifact	v7.0.2
actions/download-artifact	v8.0.2
docker/login-action	v4.6.0
docker/setup-buildx-action	v4.4.1
docker/build-push-action	v7.4.0
aquasecurity/trivy-action	v0.36.0
aquasecurity/trivy	v0.75.0
helm/kind-action	v1.15.1
azure/setup-helm	v5.0.1
gitleaks/gitleaks	v8.30.1
rhysd/actionlint	v1.7.12
semgrep/semgrep	v1.179.0
kubernetes-sigs/kind	v0.33.0
helm/helm	v4.3.0
prometheus/prometheus	v3.15.0
grafana/grafana	v13.2.3
pypa/pip-audit	v2.10.1
PyCQA/bandit	1.9.4
```

The scanners run from pinned container images (`ghcr.io/aquasecurity/trivy:0.75.0`, `ghcr.io/gitleaks/gitleaks:v8.30.1`, `mirror.gcr.io/semgrep/semgrep:1.179.0`) instead of wrapper actions, so the local runs below and CI use exactly the same tool versions and commands. Lint with actionlint (its image includes shellcheck, which checks the `run:` scripts):

```bash
$ docker run --rm -v "$PWD:/repo:ro" -w /repo mirror.gcr.io/rhysd/actionlint:1.7.12 -color=false -verbose .github/workflows/final-project.yml
verbose: Linting .github/workflows/final-project.yml
verbose: Using project at /repo
verbose: Found 0 parse errors in 3 ms for .github/workflows/final-project.yml
verbose: Found total 0 errors in 154 ms for .github/workflows/final-project.yml
exit code: 0
```

(actionlint comes from `mirror.gcr.io` because of the Docker Hub 429. I re-ran it after the last edit of the workflow, again with exit code 0.)

### Pipeline execution

TODO-POSTPUSH: link to the first GitHub Actions run of `final-project.yml` after the push, the result of each job (build-test, sast, sca, secret-scan, image, deploy-kind), the uploaded artifacts, and the GHCR packages `ghcr.io/vanshhhhhhhhh/ticketdesk-backend:<sha>` / `ticketdesk-frontend:<sha>`.

## Task 7: DevSecOps implementation

The gates and their configuration are described in [`security/README.md`](security/README.md) (`security/.gitleaks.toml`, `security/bandit.yaml`, `security/trivy.yaml`, `security/.trivyignore`, plus `.semgrepignore`). These are the local runs with the same tools and versions as the pipeline.

**SAST: Bandit and pip-audit / npm audit (SCA)**

```bash
$ bandit -c security/bandit.yaml -r application/backend/app --severity-level medium
...
Test results:
	No issues identified.
Code scanned:
	Total lines of code: 214
	Total lines skipped (#nosec): 0
...
exit code: 0
$ pip-audit -r application/backend/requirements.txt
No known vulnerabilities found
exit code: 0
$ npm audit --audit-level=high
found 0 vulnerabilities
exit code: 0
```

**SAST: Semgrep.** The first run found 11 issues in Kubernetes YAML (file names and rule IDs grepped out of the text report, then the summary at its end):

```text
$ semgrep scan --config p/python --config p/javascript --config p/dockerfile --config p/kubernetes --metrics=off --exclude node_modules --exclude dist --exclude reports --json-output=/tmp/semgrep.json --text
...
kubernetes/10-postgres.yaml
❯❱ yaml.kubernetes.security.writable-filesystem-container.writable-filesystem-container
troubleshooting/broken/ticketdesk-broken.yaml
❯❱ yaml.kubernetes.security.writable-filesystem-container.writable-filesystem-container
❱ yaml.kubernetes.security.run-as-non-root.run-as-non-root
❯❱ yaml.kubernetes.security.writable-filesystem-container.writable-filesystem-container
❱ yaml.kubernetes.security.run-as-non-root.run-as-non-root
❯❱ yaml.kubernetes.security.writable-filesystem-container.writable-filesystem-container
troubleshooting/fixed/ticketdesk-fixed.yaml
❯❱ yaml.kubernetes.security.writable-filesystem-container.writable-filesystem-container
❱ yaml.kubernetes.security.run-as-non-root.run-as-non-root
❯❱ yaml.kubernetes.security.writable-filesystem-container.writable-filesystem-container
❱ yaml.kubernetes.security.run-as-non-root.run-as-non-root
❯❱ yaml.kubernetes.security.writable-filesystem-container.writable-filesystem-container
...
 • Findings: 11 (11 blocking)
 • Rules run: 237
 • Targets scanned: 41
...
```

The real one was PostgreSQL with a writable root filesystem; I fixed it in `kubernetes/` and the Helm chart (Task 3/4). The other ten are in the troubleshooting lab manifests, which are deliberately minimal and never deployed by the pipeline, so `.semgrepignore` excludes `troubleshooting/` (and tests, build output). After that:

```bash
$ semgrep scan --config p/python --config p/javascript --config p/dockerfile --config p/kubernetes --metrics=off --error
...
✅ Scan completed successfully.
 • Findings: 0 (0 blocking)
 • Rules run: 237
 • Targets scanned: 43
 • Parsed lines: ~100.0%
 • Scan skipped: 
   ◦ Files matching .semgrepignore patterns: 32
...
Ran 237 rules on 43 files: 0 findings.
...
exit code: 0
```

**SCA + secrets: Trivy fs**

```bash
$ trivy fs --config security/trivy.yaml --scanners vuln,secret --include-dev-deps --skip-dirs application/frontend/node_modules --skip-dirs application/frontend/dist application/
Report Summary
┌────────────────────────────┬──────┬─────────────────┬─────────┐
│           Target           │ Type │ Vulnerabilities │ Secrets │
├────────────────────────────┼──────┼─────────────────┼─────────┤
│ backend/requirements.txt   │ pip  │        0        │    -    │
├────────────────────────────┼──────┼─────────────────┼─────────┤
│ frontend/package-lock.json │ npm  │        0        │    -    │
└────────────────────────────┴──────┴─────────────────┴─────────┘
...
exit code: 0
```

Without `--include-dev-deps` Trivy skipped `package-lock.json` entirely, because Vite is a devDependency (it only exists at build time).

**IaC misconfiguration: Trivy config (report only)**

```bash
$ trivy config --severity HIGH,CRITICAL --exit-code 0 --skip-dirs troubleshooting --skip-dirs application/frontend/node_modules .
...
│ docker/backend.Dockerfile                │ dockerfile │         0         │
│ docker/frontend.Dockerfile               │ dockerfile │         0         │
│ helm/ticketdesk/templates/backend.yaml   │    helm    │         0         │
...
│ kubernetes/10-postgres.yaml              │ kubernetes │         0         │
│ kubernetes/20-backend.yaml               │ kubernetes │         0         │
...
│ terraform/security-groups.tf             │ terraform  │         2         │
│ terraform/storage.tf                     │ terraform  │         1         │
...
AWS-0104 (CRITICAL): Security group rule allows unrestricted egress to any IP address.
AWS-0104 (CRITICAL): Security group rule allows unrestricted egress to any IP address.
AWS-0132 (HIGH): Bucket does not encrypt data with a customer managed key.
```

The Dockerfiles, manifests and chart are clean. The two egress rules (HTTPS to 0.0.0.0/0, needed for image pulls) and AES256 instead of a KMS key are accepted for the LocalStack lab and explained in `security/README.md`; that is why this scan reports instead of gating.

**Secrets: gitleaks.** Clean on the project folder, and to prove the gate works I ran it on a scratch copy of the config plus one planted fake connection string (the demo password on the second line is allow-listed and correctly not reported):

```bash
$ gitleaks dir final-devops-project --config final-devops-project/security/.gitleaks.toml --redact --no-banner
8:15PM INF scanned ~142034 bytes (142.03 KB) in 45.5ms
8:15PM INF no leaks found
exit code: 0
$ gitleaks dir final-devops-project --config final-devops-project/security/.gitleaks.toml --redact --no-banner   # copy with one planted fake credential
Finding:     postgresql+psycopg://ticketdesk:REDACTED@
Secret:      REDACTED
RuleID:      postgres-url-with-password
Entropy:     3.807355
File:        final-devops-project/leaked.env
Line:        1
Fingerprint: final-devops-project/leaked.env:postgres-url-with-password:1

8:12PM INF scanned ~1139 bytes (1.14 KB) in 7.44ms
8:12PM WRN leaks found: 1
exit code: 1
```

**Container images: Trivy gate.** The first image scan (HIGH/CRITICAL with a fix available) failed both images:

```text
$ jq ... first-scan JSON (before the Dockerfile fixes): HIGH/CRITICAL with a fix available, per package
== ticketdesk-backend
msgpack: 1, setuptools: 1, urllib3: 2
total: 4
== ticketdesk-frontend
c-ares: 1, curl: 10, libcrypto3: 2, libcurl: 10, libexpat: 6, libssl3: 2, libuuid: 6, libxml2: 1, pcre2: 4
total: 42
```

The backend findings were not my dependencies: they were copies of urllib3, msgpack and setuptools vendored inside `pip` itself (in the base image and in the venv). I removed pip from the runtime image. The frontend findings were Alpine packages older than the current Alpine 3.23 security updates, fixed by `apk upgrade` in the Dockerfile. After rebuilding:

```bash
$ trivy image --config security/trivy.yaml --table-mode summary ticketdesk-backend:1.0.0

Report Summary

┌──────────────────────────────────────────────────────────────────────────────────┬────────────┬─────────────────┐
│                                      Target                                      │    Type    │ Vulnerabilities │
├──────────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┤
│ ticketdesk-backend:1.0.0 (debian 13.7)                                           │   debian   │        0        │
├──────────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┤
│ opt/venv/lib/python3.12/site-packages/alembic-1.20.0.dist-info/METADATA          │ python-pkg │        0        │
...
│ opt/venv/lib/python3.12/site-packages/fastapi-0.142.2.dist-info/METADATA         │ python-pkg │        0        │
...
│ opt/venv/lib/python3.12/site-packages/sqlalchemy-2.1.4.dist-info/METADATA        │ python-pkg │        0        │
...
│ opt/venv/lib/python3.12/site-packages/uvicorn-0.54.0.dist-info/METADATA          │ python-pkg │        0        │
└──────────────────────────────────────────────────────────────────────────────────┴────────────┴─────────────────┘
...
exit code: 0
$ trivy image --config security/trivy.yaml --table-mode summary ticketdesk-frontend:1.0.0

Report Summary

┌───────────────────────────────────────────┬────────┬─────────────────┐
│                  Target                   │  Type  │ Vulnerabilities │
├───────────────────────────────────────────┼────────┼─────────────────┤
│ ticketdesk-frontend:1.0.0 (alpine 3.23.4) │ alpine │        0        │
└───────────────────────────────────────────┴────────┴─────────────────┘
...
exit code: 0
```

What the gate deliberately lets through (HIGH/CRITICAL including unfixed):

```text
$ trivy image --scanners vuln --severity HIGH,CRITICAL --format json <image> | jq (count by severity and fix status, unfixed included)
== ticketdesk-backend
HIGH affected: 43
HIGH fix_deferred: 1
== ticketdesk-frontend
```

The backend still has 44 HIGH CVEs in Debian 13 packages that Debian has not fixed ("affected") or has postponed ("fix_deferred"); there are no CRITICAL ones and the frontend has none at all. Blocking on unfixed CVEs would block every build without anything to change, so the gate is "fixable HIGH or CRITICAL", and the full list goes into the `trivy-image-reports` artifact. A distroless or Alpine-based Python image would shrink this further.

## Task 8: Monitoring

I used a lean setup instead of kube-prometheus-stack, because the cluster is shared and a second Prometheus Operator would have reconciled other people's Prometheus objects:

- **Prometheus** (`oci://ghcr.io/prometheus-community/charts/prometheus` 29.36.0, `monitoring/prometheus-values.yaml`): server only (no Alertmanager, node-exporter, kube-state-metrics or pushgateway), 2-day retention, no PVC. All chart default jobs are disabled; one job `ticketdesk-backend` discovers pods in `final-app`, `final-k8s` and `final-troubleshoot` and keeps those with `prometheus.io/scrape: "true"`, using the port/path annotations. Five alert rules: backend down, no targets, 5xx ratio > 5%, p95 > 500 ms, and a business rule (more than 10 URGENT tickets in 10 minutes).
- **Grafana** (`grafana` chart 13.3.1 from `grafana-community.github.io/helm-charts`; the old `grafana/helm-charts` repo marks it deprecated): Prometheus datasource and the dashboard `monitoring/dashboards/ticketdesk-dashboard.json` provisioned from a ConfigMap, anonymous viewer access for the screenshot, image from `mirror.gcr.io` (Docker Hub 429).

```bash
$ helm upgrade --install final-prometheus oci://ghcr.io/prometheus-community/charts/prometheus --version 29.36.0 -n final-monitoring --create-namespace -f monitoring/prometheus-values.yaml --wait
Release "final-prometheus" does not exist. Installing it now.
Pulled: ghcr.io/prometheus-community/charts/prometheus:29.36.0
Digest: sha256:a994b6672e11f3b6051bb3ff81caff34b364e1042d8d6da0b482d12a0288edbd
NAME: final-prometheus
LAST DEPLOYED: Wed Oct  7 23:45:22 2026
NAMESPACE: final-monitoring
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
...
$ kubectl -n final-monitoring create configmap final-ticketdesk-dashboard --from-file=ticketdesk.json=monitoring/dashboards/ticketdesk-dashboard.json
configmap/final-ticketdesk-dashboard created
$ helm upgrade --install final-grafana grafana --repo https://grafana-community.github.io/helm-charts --version 13.3.1 -n final-monitoring -f monitoring/grafana-values.yaml --wait
Release "final-grafana" does not exist. Installing it now.
NAME: final-grafana
LAST DEPLOYED: Wed Oct  7 23:46:40 2026
NAMESPACE: final-monitoring
STATUS: deployed
REVISION: 1
...
$ helm list -n final-monitoring
NAME            	NAMESPACE       	REVISION	UPDATED                             	STATUS  	CHART             	APP VERSION
final-grafana   	final-monitoring	2       	2026-10-07 23:56:28.848785 +0530 IST	deployed	grafana-13.3.1    	13.2.3     
final-prometheus	final-monitoring	1       	2026-10-07 23:45:22.92801 +0530 IST 	deployed	prometheus-29.36.0	v3.15.0    
```

Prometheus targets and alerts through its API (port-forward on 8440). The troubleshooting pod from Task 10 was running at the time and was scraped too, because the job covers that namespace:

```bash
$ curl -s localhost:8440/api/v1/targets | jq -r ".data.activeTargets[] | [.labels.job, .labels.namespace, .labels.pod, .health] | @tsv"
prometheus	-	-	up
ticketdesk-backend	final-app	final-ticketdesk-backend-5f6745ddfd-6ts89	up
ticketdesk-backend	final-troubleshoot	backend-74cbbc8cd8-k6fwq	up
ticketdesk-backend	final-app	final-ticketdesk-backend-5f6745ddfd-hrqfk	up
ticketdesk-backend	final-app	final-ticketdesk-backend-5f6745ddfd-lctb6	up
$ curl -s localhost:8440/api/v1/alerts | jq -r ".data.alerts[] | [.labels.alertname, .labels.namespace, .state] | @tsv"
TicketDeskUrgentTicketSpike	final-app	firing
$ curl -s "localhost:8440/api/v1/query?query=sum by (namespace) (ticketdesk_tickets_created_total)" | jq -r ".data.result[] | [.metric.namespace, .value[1]] | @tsv"
final-app	23
final-troubleshoot	1
```

The `TicketDeskUrgentTicketSpike` alert fired because I created 12 URGENT tickets in a loop to test the rule.

**Load test and autoscaling.** `scripts/load-test.sh` creates 5 urgent tickets and then runs `hey` for 120 s with 25 concurrent clients against the frontend port-forward:

```bash
$ scripts/load-test.sh http://localhost:8420 120 25

Summary:
  Total:	120.1005 secs
  Slowest:	0.4012 secs
  Fastest:	0.0015 secs
  Average:	0.0678 secs
  Requests/sec:	368.3250
  
  Total data:	290276632 bytes
  Size/request:	6562 bytes
...
$ kubectl -n final-app get hpa
NAME                       REFERENCE                             TARGETS                          MINPODS   MAXPODS   REPLICAS   AGE
final-ticketdesk-backend   Deployment/final-ticketdesk-backend   cpu: 561%/70%, memory: 55%/80%   2         5         5          4d2h
```

The same happened in the first load test on 2026-10-07, where I also captured the scale-down:

```bash
$ kubectl -n final-app describe hpa final-ticketdesk-backend | sed -n "/Events:/,$p"
Events:
  Type     Reason                        Age                From                       Message
  ----     ------                        ----               ----                       -------
  Normal   SuccessfulRescale             13m                horizontal-pod-autoscaler  New size: 2; reason: Current number of replicas below Spec.MinReplicas
...
  Normal   SuccessfulRescale             5m15s              horizontal-pod-autoscaler  New size: 5; reason: cpu resource utilization (percentage of request) above target
  Normal   SuccessfulRescale             91s                horizontal-pod-autoscaler  New size: 4; reason: All metrics below target
  Normal   SuccessfulRescale             31s                horizontal-pod-autoscaler  New size: 3; reason: All metrics below target
```

CPU utilization is measured against the 50m request, so 561% means about 280m per pod: the HPA jumped straight to the maximum of 5 and then stepped down one pod per minute (the 60 s scale-down stabilization window in the chart).

Two problems while getting the Grafana screenshot:

1. Grafana restarted during the first attempt:

   ```bash
   $ kubectl -n final-monitoring describe pod -l app.kubernetes.io/name=grafana | grep -E -A6 'Last State'
       Last State:      Terminated
         Reason:        OOMKilled
         Exit Code:     137
   ...
   ```

   Grafana 13 also downloads a set of "preinstalled" plugins at start-up. I set `plugins.preinstall_disabled: true` and raised the limit from 256Mi to 384Mi (`monitoring/grafana-values.yaml`).
2. The plain `--screenshot --virtual-time-budget` capture showed "Error loading: stat / timeseries" in every panel. Grafana lazy-loads its panel plugins, and virtual time fired the loaders' timeouts before the files arrived. `scripts/screenshot-cdp.mjs` drives the same headless Chrome over the DevTools protocol and waits 20 s of real time before capturing.

I also changed the "5xx error ratio" query to `(... or vector(0))`, because with no 5xx responses at all the series did not exist and the panel said "No data" instead of 0%.

![Grafana dashboard during the load test](screenshots/04-grafana-dashboard.png)

![Prometheus targets: the backend pods UP](screenshots/05-prometheus-targets.png)

![Prometheus alert rules, one firing](screenshots/06-prometheus-alerts.png)

Logs: the backend logs one line per ticket change (`ticket created id=... priority=...`) plus uvicorn access logs, read with `kubectl logs`; the troubleshooting section uses them, together with the ingress-nginx access log.

## Task 9: GitOps

`gitops/argocd-application.yaml` defines an Argo CD `Application` named `final-ticketdesk`: source `https://github.com/vanshhhhhhhhh/DevOPS-ASSIGNMENT-VANSH-SRIVASTAVA.git`, `targetRevision: main`, `path: final-devops-project/helm/ticketdesk`, value file `values-minikube.yaml`, destination namespace `final-app`, automated sync with `prune` and `selfHeal`, `CreateNamespace=true` and a retry policy. The Helm `releaseName` is `final-ticketdesk`, the same as my manual release, so Argo CD renders identical object names and takes over the objects that are already running instead of creating a second copy. There is no `resources-finalizer`, so deleting the Application does not delete the app.

Argo CD v3.5.4 runs in the shared namespace `argocd`. Before the push I only validated the manifest against the cluster's CRD with a server-side dry run (nothing is created):

```bash
$ kubectl apply --dry-run=server -f gitops/argocd-application.yaml
application.argoproj.io/final-ticketdesk created (server dry run)
$ kubectl -n argocd get applications
No resources found in argocd namespace.
```

The workflow pushes SHA-tagged images to GHCR, but the Application uses the locally loaded `1.0.0` images from `values-minikube.yaml`, so the GitOps demo does not depend on the GHCR packages being public. Switching it to GHCR means setting `backend.image.repository/tag` and `frontend.image.repository/tag` to the pushed SHA in Git; Argo CD then rolls the pods.

### GitOps sync (after the push)

TODO-POSTPUSH: output of the live sync, run after the repository was pushed:

```bash
$ kubectl apply -f final-devops-project/gitops/argocd-application.yaml
$ kubectl -n argocd get application final-ticketdesk -o wide
$ kubectl -n argocd get application final-ticketdesk -o jsonpath='{.status.sync.status} {.status.health.status} {.status.sync.revision}'
$ kubectl -n final-app get pods
```

Optional self-heal demo: `kubectl -n final-app scale deploy/final-ticketdesk-frontend --replicas=1`, then watch Argo CD put it back to 2.

## Task 10: Final Troubleshooting Challenge

`troubleshooting/broken/ticketdesk-broken.yaml` deploys TicketDesk into `final-troubleshoot` with six planted faults; `troubleshooting/fixed/ticketdesk-fixed.yaml` is the corrected version (each fix is marked `FIX n`). The faults hide behind each other, so they show up one at a time, the way they would in a real incident.

```bash
$ kubectl apply -f troubleshooting/broken/ticketdesk-broken.yaml
namespace/final-troubleshoot created
configmap/ticketdesk-config created
secret/ticketdesk-db created
service/postgres created
statefulset.apps/postgres created
deployment.apps/backend created
service/backend created
deployment.apps/frontend created
service/frontend created
ingress.networking.k8s.io/ticketdesk created
horizontalpodautoscaler.autoscaling/backend created
$ kubectl -n final-troubleshoot get pods
NAME                        READY   STATUS             RESTARTS   AGE
backend-58f556f64-bdz8b     0/1     ImagePullBackOff   0          18s
frontend-68b54f6647-79pjq   1/1     Running            0          18s
postgres-0                  1/1     Running            0          18s
```

### Issue 1: wrong image tag (ImagePullBackOff)

**Investigate:**

```bash
$ kubectl -n final-troubleshoot describe pod -l app=ticketdesk-backend
Containers:
  backend:
    Container ID:   
    Image:          ticketdesk-backend:1.0.1
    Image ID:       
    Port:           8000/TCP (http)
    Host Port:      0/TCP (http)
    State:          Waiting
      Reason:       ImagePullBackOff
    Ready:          False
...
Events:
  Type     Reason     Age               From               Message
  ----     ------     ----              ----               -------
  Normal   Scheduled  23s               default-scheduler  Successfully assigned final-troubleshoot/backend-58f556f64-bdz8b to minikube
  Normal   BackOff    21s               kubelet            spec.containers{backend}: Back-off pulling image "ticketdesk-backend:1.0.1"
  Warning  Failed     21s               kubelet            spec.containers{backend}: Error: ImagePullBackOff
  Normal   Pulling    5s (x2 over 23s)  kubelet            spec.containers{backend}: Pulling image "ticketdesk-backend:1.0.1"
  Warning  Failed     3s (x2 over 21s)  kubelet            spec.containers{backend}: Failed to pull image "ticketdesk-backend:1.0.1": failed to pull and unpack image "docker.io/library/ticketdesk-backend:1.0.1": failed to resolve reference "docker.io/library/ticketdesk-backend:1.0.1": pull access denied, repository does not exist or may require authorization: server message: insufficient_scope: authorization failed
  Warning  Failed     3s (x2 over 21s)  kubelet            spec.containers{backend}: Error: ErrImagePull
$ minikube image ls | grep ticketdesk-backend
docker.io/library/ticketdesk-backend:1.0.0
```

**Root cause:** tag `1.0.1` was never built. It is not in the node's image store, so with `IfNotPresent` the kubelet tried Docker Hub, where the repository does not exist. Only `1.0.0` was loaded.

**Fix:**

```bash
$ kubectl -n final-troubleshoot set image deploy/backend backend=ticketdesk-backend:1.0.0
deployment.apps/backend image updated
```

### Issue 2: Secret key missing (CreateContainerConfigError)

**Investigate:** the new pod could not even be created:

```bash
$ kubectl -n final-troubleshoot get pods -l app=ticketdesk-backend
NAME                      READY   STATUS                       RESTARTS   AGE
backend-58f556f64-bdz8b   0/1     ErrImagePull                 0          35s
backend-959dd956c-b67wh   0/1     CreateContainerConfigError   0          2s
$ kubectl -n final-troubleshoot get events --field-selector reason=Failed --sort-by=.lastTimestamp | tail -2
1s          Warning   Failed   pod/backend-959dd956c-b67wh   Error: couldn't find key DB_PASSWORD in Secret final-troubleshoot/ticketdesk-db
0s          Warning   Failed   pod/backend-58f556f64-bdz8b   Error: ImagePullBackOff
$ kubectl -n final-troubleshoot get secret ticketdesk-db -o jsonpath="{.data}" | jq "keys"
["POSTGRES_PASSWORD"]
```

**Root cause:** the Deployment reads `secretKeyRef.key: DB_PASSWORD`, but the Secret only has `POSTGRES_PASSWORD` (the key Postgres uses). The kubelet refuses to start a container whose env refers to a missing key.

**Fix:**

```bash
$ kubectl -n final-troubleshoot patch deploy/backend --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/env/0/valueFrom/secretKeyRef/key","value":"POSTGRES_PASSWORD"}]'
deployment.apps/backend patched
```

### Issue 3: readiness probe on the wrong path (Running but never Ready)

**Investigate:**

```bash
$ kubectl -n final-troubleshoot get pods -l app=ticketdesk-backend
NAME                       READY   STATUS                       RESTARTS   AGE
backend-79b9445bd4-6zmv6   0/1     Running                      0          8s
backend-959dd956c-b67wh    0/1     CreateContainerConfigError   0          19s
$ kubectl -n final-troubleshoot describe pod -l app=ticketdesk-backend | grep -E "Readiness|Unhealthy"
    Readiness:      http-get http://:http/readyz delay=0s timeout=1s period=5s successThreshold=1 failureThreshold=3
    Readiness:      http-get http://:http/readyz delay=0s timeout=1s period=5s successThreshold=1 failureThreshold=3
$ kubectl -n final-troubleshoot logs deploy/backend --tail=3
Found 2 pods, using pod/backend-79b9445bd4-6zmv6
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
INFO:     10.244.0.3:57566 - "GET /metrics HTTP/1.1" 200 OK
INFO:     10.244.0.1:48336 - "GET /readyz HTTP/1.1" 404 Not Found
$ kubectl -n final-troubleshoot get events --field-selector reason=Unhealthy
LAST SEEN   TYPE      REASON      OBJECT                          MESSAGE
14s         Warning   Unhealthy   pod/backend-79b9445bd4-6zmv6    Readiness probe failed: Get "http://10.244.0.27:8000/readyz": dial tcp 10.244.0.27:8000: connect: connection refused
4s          Warning   Unhealthy   pod/backend-79b9445bd4-6zmv6    Readiness probe failed: HTTP probe failed with statuscode: 404
...
$ kubectl -n final-troubleshoot exec deploy/frontend -- wget -qO- http://<backend-pod-ip>:8000/ready
{"status":"ready","database":"up"}
```

**Root cause:** the app is healthy (the database answers and `/ready` returns 200, called from another pod), but the probe asks for `/readyz`, which returns 404, so the pod never becomes Ready and never gets traffic. Interesting detail: Prometheus was already scraping `/metrics` on the unready pod, because pod discovery does not care about readiness.

**Fix:**

```bash
$ kubectl -n final-troubleshoot patch deploy/backend --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/ready"}]'
deployment.apps/backend patched
$ kubectl -n final-troubleshoot rollout status deploy/backend
...
deployment "backend" successfully rolled out
$ kubectl -n final-troubleshoot get pods
NAME                        READY   STATUS        RESTARTS   AGE
backend-6b96bccdc6-wnfcg    1/1     Running       0          5s
backend-79b9445bd4-6zmv6    0/1     Terminating   0          31s
frontend-68b54f6647-79pjq   1/1     Running       0          75s
postgres-0                  1/1     Running       0          75s
```

### Issue 4: Service selector does not match the pods (502 from nginx)

**Investigate:** everything is Running and Ready, but the API is unreachable through the frontend:

```bash
$ kubectl -n final-troubleshoot port-forward svc/frontend 8450:80 &
$ curl -s -i localhost:8450/api/health | head -1
HTTP/1.1 502 Bad Gateway
$ kubectl -n final-troubleshoot get endpointslices -l kubernetes.io/service-name=backend
NAME            ADDRESSTYPE   PORTS     ENDPOINTS   AGE
backend-lc9rw   IPv4          <unset>   <unset>     77s
$ kubectl -n final-troubleshoot get svc backend -o jsonpath="{.spec.selector}"
{"app":"ticketdesk-api"}
$ kubectl -n final-troubleshoot get pods -l app=ticketdesk-backend --show-labels
NAME                       READY   STATUS    RESTARTS   AGE   LABELS
backend-6b96bccdc6-wnfcg   1/1     Running   0          7s    app=ticketdesk-backend,pod-template-hash=6b96bccdc6
$ kubectl -n final-troubleshoot logs deploy/frontend --tail=2
127.0.0.1 - - [07/Oct/2026:18:20:52 +0000] "GET /api/health HTTP/1.1" 502 150 "-" "curl/8.7.1" "-"
2026/10/07 18:20:52 [error] 35#35: *9 connect() failed (111: Connection refused) while connecting to upstream, client: 127.0.0.1, server: _, request: "GET /api/health HTTP/1.1", upstream: "http://10.99.152.105:8000/api/health", host: "localhost:8450"
```

**Root cause:** the Service selects `app=ticketdesk-api`, the pods are labelled `app=ticketdesk-backend`, so the Service has no endpoints and connections to its ClusterIP are refused.

**Fix and verify:**

```bash
$ kubectl -n final-troubleshoot patch svc/backend -p '{"spec":{"selector":{"app":"ticketdesk-backend"}}}'
service/backend patched
$ kubectl -n final-troubleshoot get endpointslices -l kubernetes.io/service-name=backend
NAME            ADDRESSTYPE   PORTS   ENDPOINTS     AGE
backend-lc9rw   IPv4          8000    10.244.0.28   89s
$ curl -s -i localhost:8450/api/health | sed -n "1p;$p"
HTTP/1.1 200 OK
{"status":"ok"}
```

### Issue 5: Ingress points at the wrong Service port (503)

**Investigate:** through the shared ingress-nginx controller, `/` works but `/api` does not:

```bash
$ curl -s -i -H "Host: troubleshoot.final.local" localhost:8430/ | head -1
HTTP/1.1 200 OK
$ curl -s -i -H "Host: troubleshoot.final.local" localhost:8430/api/health | head -1
HTTP/1.1 503 Service Temporarily Unavailable
$ kubectl -n final-troubleshoot describe ingress ticketdesk | sed -n "/Rules:/,/Events/p"
Rules:
  Host                      Path  Backends
  ----                      ----  --------
  troubleshoot.final.local  
                            /api   backend:8080 ()
                            /      frontend:80 (10.244.0.22:8080)
Annotations:                <none>
Events:
$ kubectl -n final-troubleshoot get svc backend
NAME      TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
backend   ClusterIP   10.99.152.105   <none>        8000/TCP   89s
$ kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --since=3m | grep 'GET /api/health' | grep ' 503 ' | tail -1
127.0.0.1 - - [07/Oct/2026:18:21:04 +0000] "GET /api/health HTTP/1.1" 503 190 "-" "curl/8.7.1" 97 0.000 [final-troubleshoot-backend-8080] [] - - - - 477f18c766dce210f67c0eac508da241
```

**Root cause:** the Ingress sends `/api` to port 8080 of Service `backend`, which only exposes 8000. `describe` shows no endpoints for `backend:8080` (empty parentheses), and the controller's access log shows upstream `final-troubleshoot-backend-8080` with an empty address list, so it answers 503 itself.

**Fix and verify:**

```bash
$ kubectl -n final-troubleshoot patch ingress/ticketdesk --type=json -p '[{"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service/port/number","value":8000}]'
ingress.networking.k8s.io/ticketdesk patched
$ kubectl -n final-troubleshoot describe ingress ticketdesk | grep -A3 "Host "
  Host                      Path  Backends
  ----                      ----  --------
  troubleshoot.final.local  
                            /api   backend:8000 (10.244.0.28:8000)
$ curl -s -i -H "Host: troubleshoot.final.local" localhost:8430/api/health | sed -n "1p;$p"
HTTP/1.1 200 OK
{"status":"ok"}
```

### Issue 6: HPA on a container without resource requests

**Investigate:**

```bash
$ kubectl -n final-troubleshoot get hpa backend
NAME      REFERENCE            TARGETS              MINPODS   MAXPODS   REPLICAS   AGE
backend   Deployment/backend   cpu: <unknown>/70%   1         3         1          3m1s
$ kubectl -n final-troubleshoot describe hpa backend | grep "missing request" | tail -1
  Warning  FailedGetResourceMetric       1s                  horizontal-pod-autoscaler  failed to get cpu utilization: missing request for cpu in container backend of Pod backend-6b96bccdc6-wnfcg
$ kubectl -n final-troubleshoot top pod -l app=ticketdesk-backend
NAME                       CPU(cores)   MEMORY(bytes)   
backend-6b96bccdc6-wnfcg   4m           63Mi            
$ kubectl -n final-troubleshoot get deploy backend -o jsonpath="{.spec.template.spec.containers[0].resources}"
{}
```

**Root cause:** metrics-server has the numbers (`kubectl top` shows 4m), but the HPA target is a percentage *of the request*, and the container has no requests (`{}`), so the utilization cannot be computed and the HPA would never scale. (Right after the earlier fixes the message was still "no metrics returned from resource metrics API", because metrics-server had not scraped the new pod yet; the real cause only showed after a minute.)

**Fix and verify:**

```bash
$ kubectl -n final-troubleshoot set resources deploy/backend --requests=cpu=50m,memory=128Mi --limits=cpu=500m,memory=256Mi
deployment.apps/backend resource requirements updated
Waiting for deployment "backend" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "backend" rollout to finish: 1 old replicas are pending termination...
deployment "backend" successfully rolled out
$ kubectl -n final-troubleshoot get hpa backend
NAME      REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
backend   Deployment/backend   cpu: 6%/70%   1         3         1          5m
$ kubectl -n final-troubleshoot describe hpa backend | grep ScalingActive
  ScalingActive   True    ValidMetricFound    the HPA was able to successfully calculate a replica count from cpu resource utilization (percentage of request)
```

### Making the fixes permanent

The live fixes were imperative (`set image`, `patch`, `set resources`), as they would be during an incident. Afterwards the fixed manifest is the source of truth: `kubectl diff` showed no differences other than the `last-applied-configuration` annotation, applying it restarted nothing (pod ages unchanged), and the full smoke test passes through the Ingress:

```bash
$ kubectl diff -f troubleshooting/fixed/ticketdesk-fixed.yaml | grep -E "^[-+] " | grep -v -E "last-applied-configuration|generation:" | wc -l
       0
$ kubectl apply -f troubleshooting/fixed/ticketdesk-fixed.yaml
namespace/final-troubleshoot unchanged
configmap/ticketdesk-config unchanged
secret/ticketdesk-db configured
service/postgres unchanged
statefulset.apps/postgres configured
deployment.apps/backend configured
service/backend configured
deployment.apps/frontend unchanged
service/frontend unchanged
ingress.networking.k8s.io/ticketdesk configured
horizontalpodautoscaler.autoscaling/backend unchanged
$ kubectl -n final-troubleshoot get pods,endpointslices,hpa
NAME                            READY   STATUS    RESTARTS   AGE
pod/backend-74cbbc8cd8-k6fwq    1/1     Running   0          2m6s
pod/frontend-68b54f6647-79pjq   1/1     Running   0          5m14s
pod/postgres-0                  1/1     Running   0          5m14s

NAME                                            ADDRESSTYPE   PORTS   ENDPOINTS     AGE
endpointslice.discovery.k8s.io/backend-lc9rw    IPv4          8000    10.244.0.31   5m14s
endpointslice.discovery.k8s.io/frontend-sqtsl   IPv4          8080    10.244.0.22   5m14s
endpointslice.discovery.k8s.io/postgres-5ldrf   IPv4          5432    10.244.0.21   5m14s

NAME                                          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/backend   Deployment/backend   cpu: 6%/70%   1         3         1          5m14s
$ scripts/smoke-test.sh http://localhost:8430 troubleshoot.final.local | tail -1
SMOKE TEST PASSED against http://localhost:8430
```

| # | Symptom | Where I saw it | Root cause | Fix |
|---|---------|----------------|------------|-----|
| 1 | `ImagePullBackOff` | `describe pod` events | tag `1.0.1` does not exist | `set image ... :1.0.0` |
| 2 | `CreateContainerConfigError` | events | env refers to Secret key `DB_PASSWORD`, Secret has `POSTGRES_PASSWORD` | point `secretKeyRef.key` at the existing key |
| 3 | Running, `0/1` Ready | `describe pod`, events, app log (`GET /readyz 404`) | probe path `/readyz` | probe `/ready` |
| 4 | 502 from nginx, no endpoints | EndpointSlice, `--show-labels`, nginx error log | selector `app=ticketdesk-api` | selector `app=ticketdesk-backend` |
| 5 | 503 on `/api` via Ingress | `describe ingress`, controller access log | Ingress port 8080, Service port 8000 | port 8000 |
| 6 | HPA `<unknown>` | `describe hpa`: missing request for cpu | no resource requests | add requests/limits |

I deleted `final-troubleshoot` after capturing this.

## Screenshots

| File | What it shows |
|------|---------------|
| [01-app-ui-compose.png](screenshots/01-app-ui-compose.png) | TicketDesk UI from docker compose (http://localhost:8400) |
| [02-api-docs-swagger.png](screenshots/02-api-docs-swagger.png) | FastAPI Swagger UI at `/api/docs` |
| [03-app-ui-k8s-ingress.png](screenshots/03-app-ui-k8s-ingress.png) | the Helm release through ingress-nginx, host `ticketdesk.final.local` |
| [04-grafana-dashboard.png](screenshots/04-grafana-dashboard.png) | Grafana "TicketDesk - API overview" during the load test (5 pods after HPA scale-up) |
| [05-prometheus-targets.png](screenshots/05-prometheus-targets.png) | Prometheus target health: all backend pods UP |
| [06-prometheus-alerts.png](screenshots/06-prometheus-alerts.png) | the five alert rules, `TicketDeskUrgentTicketSpike` firing |

All were taken with headless Chrome; 04 through `scripts/screenshot-cdp.mjs` for the reason given in Task 8.

## What I learned

- A headless Service name does not resolve until a pod behind it is Ready, so an app that runs migrations at start-up has to retry instead of crash-looping; a PostgreSQL advisory lock keeps two replicas from migrating at the same time.
- Most of my image CVEs were not in my code or my dependencies: they were pip's own vendored libraries and stale Alpine packages. Removing pip from the runtime image and upgrading OS packages in the Dockerfile cleared them. A gate on *fixable* HIGH/CRITICAL is strict but still passable; blocking on unfixed CVEs would block every build.
- HPA percentages are relative to requests: no requests means `<unknown>` and no scaling, and a request that is too small (50m) makes ordinary load look like 561%.
- In Kubernetes troubleshooting, each layer hides the next one (image -> config -> probe -> Service -> Ingress -> HPA). `describe` + events find the first three, EndpointSlices and labels the fourth, `describe ingress` and the controller log the fifth.
- Scanner results depend on scope: Trivy skipped the npm lockfile until I added `--include-dev-deps`; gitleaks has to be scoped to this folder because the rest of the repo contains intentional fake secrets; Semgrep's useful finding (Postgres with a writable root FS) was next to ten findings in deliberately broken lab files.
- Real tool constraints showed up that tutorials skip: S3 tag values cannot contain parentheses, Docker Hub rate-limits anonymous pulls (mirrors fix it), Grafana 13 needs more than 256Mi when it installs plugins, and `--virtual-time-budget` breaks lazily loaded web apps.
- On a shared cluster, a lean Prometheus (no operator) with namespace-restricted discovery avoids interfering with other people's monitoring.
