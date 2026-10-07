# Node.js Hello World. No npm dependencies, so a single small stage is enough.
# Base image: official node:24-alpine, pulled through the AWS ECR Public mirror of
# Docker Hub's official images (Docker Hub was rate-limiting anonymous pulls).
FROM public.ecr.aws/docker/library/node:24-alpine

WORKDIR /app
ENV NODE_ENV=production PORT=3000

COPY package.json server.js ./

# The node image ships a non-root "node" user; use it instead of root.
USER node

EXPOSE 3000
CMD ["node", "server.js"]
