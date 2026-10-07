# Frontend: nginx serving a static page and proxying /api/ to the backend container.
# Base image: official nginx:1.29-alpine via the AWS ECR Public mirror of Docker Hub.
FROM public.ecr.aws/docker/library/nginx:1.29-alpine
COPY default.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
