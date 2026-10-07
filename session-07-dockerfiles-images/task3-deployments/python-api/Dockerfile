# MULTI-STAGE version.
#   build:   full python:3.13 image installs the dependencies into a virtualenv (/opt/venv)
#   runtime: python:3.13-slim gets only that virtualenv and app.py
# Both stages use the same Python build (/usr/local/bin/python3.13), so the venv works
# unchanged after it is copied.
# Base images: official python images via the AWS ECR Public mirror of Docker Hub.

FROM public.ecr.aws/docker/library/python:3.13 AS build
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM public.ecr.aws/docker/library/python:3.13-slim AS runtime
COPY --from=build /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH" PYTHONUNBUFFERED=1 IMAGE_VARIANT=multi-stage
WORKDIR /app
COPY app.py .
RUN useradd --no-create-home --shell /usr/sbin/nologin appuser
USER appuser
EXPOSE 5000
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--access-logfile", "-", "app:app"]
