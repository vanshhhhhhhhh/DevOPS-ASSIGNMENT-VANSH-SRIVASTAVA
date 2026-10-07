# React Hello World, multi-stage:
#   stage 1 (build): Node installs the exact locked dependencies and runs `vite build`
#   stage 2 (run):   nginx serves only the generated static files from /app/dist
# Node, npm and node_modules never reach the final image.
# Base images: official node / nginx images via the AWS ECR Public mirror of Docker Hub.

FROM public.ecr.aws/docker/library/node:24-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY index.html vite.config.js ./
COPY src ./src
RUN npm run build

FROM public.ecr.aws/docker/library/nginx:1.29-alpine
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
