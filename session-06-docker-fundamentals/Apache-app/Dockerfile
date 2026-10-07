# Apache HTTP Server (httpd) serving one static Hello World page.
# Base image: official httpd:2.4-alpine via the AWS ECR Public mirror of Docker Hub.
FROM public.ecr.aws/docker/library/httpd:2.4-alpine

# httpd's document root in the official image is /usr/local/apache2/htdocs/
COPY index.html /usr/local/apache2/htdocs/index.html

EXPOSE 80
# The base image already runs: CMD ["httpd-foreground"]
