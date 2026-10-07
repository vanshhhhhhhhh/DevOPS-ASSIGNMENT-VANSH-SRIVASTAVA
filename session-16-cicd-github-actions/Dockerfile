# Session 16 calculator service.
# Base: the official python:3.14-slim-trixie image, pulled through the AWS ECR Public mirror of
# Docker Hub's official images, because Docker Hub answered my pulls with 429 Too Many Requests
# (see README). Same image; override with --build-arg PYTHON_IMAGE=python:3.14-slim-trixie if wanted.
ARG PYTHON_IMAGE=public.ecr.aws/docker/library/python:3.14-slim-trixie
FROM ${PYTHON_IMAGE}

# Filled in by the CI pipeline (docker build --build-arg ...) and shown by /api/info.
ARG APP_VERSION=dev
ARG GIT_SHA=local

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    APP_VERSION=${APP_VERSION} \
    GIT_SHA=${GIT_SHA}

LABEL org.opencontainers.image.source="https://github.com/vanshhhhhhhhh/DevOPS-ASSIGNMENT-VANSH-SRIVASTAVA" \
      org.opencontainers.image.description="Session 16 CI/CD demo (calculator API)" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}"

WORKDIR /app

# Dependencies first so this layer is cached when only the code changes.
COPY requirements.txt .
RUN pip install --no-cache-dir --root-user-action=ignore -r requirements.txt

COPY app ./app

# Run as an unprivileged user (numeric UID so Kubernetes can verify runAsNonRoot).
RUN useradd --system --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser
USER 10001

EXPOSE 8000
# --no-control-socket: gunicorn 26 would otherwise create a control socket in $HOME, which this user does not have.
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "--no-control-socket", "--access-logfile", "-", "app.main:app"]
