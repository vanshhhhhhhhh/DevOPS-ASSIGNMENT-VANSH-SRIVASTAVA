# Nginx serving one static Hello World page.
# Base image: official nginx:1.29-alpine via the AWS ECR Public mirror of Docker Hub.
FROM public.ecr.aws/docker/library/nginx:1.29-alpine

COPY index.html /usr/share/nginx/html/index.html

EXPOSE 80
# The base image already runs: CMD ["nginx", "-g", "daemon off;"]
