# syntax=docker/dockerfile:1
# Frontend image for TicketDesk. Build context: application/frontend
#   docker build -f docker/frontend.Dockerfile -t ticketdesk-frontend:1.0.0 application/frontend
# Stage 1 builds the static site with Node; stage 2 serves it with an
# unprivileged nginx (runs as uid 101, listens on 8080), so no Node tooling
# ends up in the runtime image.

FROM public.ecr.aws/docker/library/node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY index.html vite.config.js ./
COPY public ./public
COPY src ./src
RUN npm run build

FROM public.ecr.aws/nginx/nginx-unprivileged:1.29-alpine AS runtime
LABEL org.opencontainers.image.title="ticketdesk-frontend" \
      org.opencontainers.image.description="TicketDesk web UI served by nginx" \
      org.opencontainers.image.source="https://github.com/vanshhhhhhhhh/DevOPS-ASSIGNMENT-VANSH-SRIVASTAVA" \
      org.opencontainers.image.licenses="MIT"
# Where nginx proxies /api/ to; overridden per environment.
ENV BACKEND_URL=http://backend:8000
# The base image lags behind Alpine security updates (curl, openssl, expat, pcre2
# were HIGH findings in the first Trivy scan), so upgrade the OS packages.
USER root
RUN apk upgrade --no-cache
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /app/dist /usr/share/nginx/html
USER 101
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
