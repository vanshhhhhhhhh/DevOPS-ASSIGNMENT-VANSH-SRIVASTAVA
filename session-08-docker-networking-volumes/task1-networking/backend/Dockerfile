# Backend: nginx returning a small JSON status document.
# Base image: official nginx:1.29-alpine via the AWS ECR Public mirror of Docker Hub.
FROM public.ecr.aws/docker/library/nginx:1.29-alpine
COPY default.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
