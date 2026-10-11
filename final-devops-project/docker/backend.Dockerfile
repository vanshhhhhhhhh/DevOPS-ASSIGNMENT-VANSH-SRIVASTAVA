# Backend image for TicketDesk (FastAPI). Build context: application/backend
#   docker build -f docker/backend.Dockerfile -t ticketdesk-backend:1.0.0 application/backend
# Base images come from the ECR Public mirror of the Docker official images
# (same images as Docker Hub, without the anonymous pull rate limit).

FROM public.ecr.aws/docker/library/python:3.12-slim AS build
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /build
COPY requirements.txt .
RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install -r requirements.txt \
 && /opt/venv/bin/pip uninstall -y pip

FROM public.ecr.aws/docker/library/python:3.12-slim AS runtime
LABEL org.opencontainers.image.title="ticketdesk-backend" \
      org.opencontainers.image.description="TicketDesk support-ticket API (FastAPI)" \
      org.opencontainers.image.source="https://github.com/vanshhhhhhhhh/DevOPS-ASSIGNMENT-VANSH-SRIVASTAVA" \
      org.opencontainers.image.licenses="MIT"
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    PORT=8000
# Pull in Debian security fixes that are newer than the base image, and remove
# pip from the runtime image: it is not needed to run the app, and its vendored
# copies of urllib3/msgpack/setuptools were the HIGH findings of the first Trivy scan.
RUN apt-get update \
 && apt-get upgrade -y --no-install-recommends \
 && rm -rf /var/lib/apt/lists/* \
 && python -m pip uninstall -y pip \
 && groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app
WORKDIR /app
COPY --from=build /opt/venv /opt/venv
COPY --chown=root:root alembic.ini start.sh ./
COPY --chown=root:root alembic ./alembic
COPY --chown=root:root app ./app
USER 10001:10001
EXPOSE 8000
HEALTHCHECK --interval=15s --timeout=3s --start-period=20s --retries=3 \
  CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2).status == 200 else 1)"]
CMD ["/app/start.sh"]
