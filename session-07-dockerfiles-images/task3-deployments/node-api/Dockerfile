# MULTI-STAGE version.
#   build:   full node:24 image, installs dev dependencies and compiles TypeScript -> dist/
#   runtime: small node:24-alpine image with only the compiled dist/ folder.
# The app has no runtime npm dependencies, so no node_modules are copied at all.
# Base images: official node images via the AWS ECR Public mirror of Docker Hub.

FROM public.ecr.aws/docker/library/node:24 AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

FROM public.ecr.aws/docker/library/node:24-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production PORT=3000 IMAGE_VARIANT=multi-stage
COPY --from=build /app/package.json ./
COPY --from=build /app/dist ./dist
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1:3000/health || exit 1
CMD ["node", "dist/server.js"]
