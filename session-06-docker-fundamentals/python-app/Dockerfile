# Python Hello World using only the standard library, so there is no pip install step.
# Base image: official python:3.13-alpine via the AWS ECR Public mirror of Docker Hub.
FROM public.ecr.aws/docker/library/python:3.13-alpine

WORKDIR /app
ENV PYTHONUNBUFFERED=1 PORT=5000

COPY app.py .

# Run as an unprivileged user.
RUN adduser -D -H appuser
USER appuser

EXPOSE 5000
CMD ["python", "app.py"]
