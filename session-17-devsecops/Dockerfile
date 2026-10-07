# Session 17 DevSecOps demo image.
# Base: python:3.14-alpine. I scanned it against python:3.14-slim-trixie with Trivy before choosing
# (see README, Task 1): the Debian slim image had 44 HIGH OS CVEs without a fix, Alpine had none.
# It is pulled through the AWS ECR Public mirror of Docker Hub's official images because Docker Hub
# answered my pulls with 429 Too Many Requests (see README). Same image, also used in CI.
ARG PYTHON_IMAGE=public.ecr.aws/docker/library/python:3.14-alpine

# ---------- stage 1: install dependencies into a virtualenv ----------
FROM ${PYTHON_IMAGE} AS deps
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1
COPY requirements.txt /tmp/requirements.txt
# pip is removed from the venv after use: the runtime never installs packages.
RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install -r /tmp/requirements.txt \
 && /opt/venv/bin/pip uninstall -y pip

# ---------- stage 2: minimal runtime ----------
FROM ${PYTHON_IMAGE}

ARG APP_VERSION=dev
ARG GIT_SHA=local

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:${PATH}" \
    APP_VERSION=${APP_VERSION} \
    GIT_SHA=${GIT_SHA}

LABEL org.opencontainers.image.source="https://github.com/vanshhhhhhhhh/DevOPS-ASSIGNMENT-VANSH-SRIVASTAVA" \
      org.opencontainers.image.description="Session 17 DevSecOps demo (notes API)" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}"

# 1. apk upgrade: apply Alpine security fixes published after the base image was built
#    (my first scan found zlib CVE-2026-85091, fixed in 1.3.2-r1).
# 2. Remove the base image's own pip (Trivy flags the libraries pip vendors).
# 3. Add a dedicated unprivileged user with a numeric UID/GID above 10000.
RUN apk upgrade --no-cache \
 && python -m pip uninstall -y --root-user-action=ignore pip \
 && addgroup -S -g 10001 app \
 && adduser -S -D -H -u 10001 -G app -s /sbin/nologin app

COPY --from=deps /opt/venv /opt/venv
WORKDIR /app
COPY app ./app

USER 10001:10001
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=2)"]

# One worker + threads keeps the in-memory notes consistent. The heartbeat file goes to /dev/shm and
# the control socket is disabled, so nothing needs to write to the (read-only) root filesystem.
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "1", "--threads", "4", \
     "--worker-tmp-dir", "/dev/shm", "--no-control-socket", "--access-logfile", "-", "app.main:app"]
