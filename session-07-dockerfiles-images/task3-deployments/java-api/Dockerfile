# MULTI-STAGE version.
#   build:   JDK (Alpine) compiles the code, packages app.jar and uses jlink to create a
#            custom Java runtime that contains only the 3 modules the app needs
#            (java.base, java.management, jdk.httpserver).
#   runtime: plain alpine:3.22 + that custom runtime + app.jar. No JDK, no javac.
# The JDK stage is Alpine (musl libc) so the jlink output runs on the Alpine runtime.
# Base images: official images via the AWS ECR Public mirror of Docker Hub.

FROM public.ecr.aws/docker/library/eclipse-temurin:21-jdk-alpine AS build
WORKDIR /build
COPY src ./src
RUN javac -d classes src/InfoApi.java \
 && jar --create --file app.jar --main-class InfoApi -C classes . \
 && jlink --add-modules java.base,java.management,jdk.httpserver \
          --strip-debug --no-man-pages --no-header-files --compress=zip-6 \
          --output /opt/jre

FROM public.ecr.aws/docker/library/alpine:3.22 AS runtime
COPY --from=build /opt/jre /opt/jre
COPY --from=build /build/app.jar /app/app.jar
RUN adduser -D -H appuser
USER appuser
ENV PATH="/opt/jre/bin:$PATH" PORT=8080 IMAGE_VARIANT=multi-stage
EXPOSE 8080
CMD ["java", "-jar", "/app/app.jar"]
