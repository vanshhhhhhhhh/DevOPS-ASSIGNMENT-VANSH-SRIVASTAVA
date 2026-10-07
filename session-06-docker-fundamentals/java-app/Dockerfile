# Java Hello World, multi-stage:
#   stage 1 (build): full JDK compiles the source with javac
#   stage 2 (run):   only the JRE plus the compiled .class file
# Base images: official eclipse-temurin images via the AWS ECR Public mirror of Docker Hub.

FROM public.ecr.aws/docker/library/eclipse-temurin:21-jdk-alpine AS build
WORKDIR /src
COPY src/HelloWorld.java .
RUN javac -d /out HelloWorld.java

FROM public.ecr.aws/docker/library/eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=build /out/ ./
RUN adduser -D -H appuser
USER appuser
ENV PORT=8080
EXPOSE 8080
CMD ["java", "-cp", "/app", "HelloWorld"]
