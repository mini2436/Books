# syntax=docker/dockerfile:1.7

FROM eclipse-temurin:21-jdk@sha256:e58e492628c1428ceb838afc1a1b8762673d5eaa09296f560c363daea0fdcf3b AS builder
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY
ARG GRADLE_PROXY_HOST
ARG GRADLE_PROXY_PORT
ENV HTTP_PROXY=$HTTP_PROXY \
    HTTPS_PROXY=$HTTPS_PROXY \
    NO_PROXY=$NO_PROXY \
    http_proxy=$HTTP_PROXY \
    https_proxy=$HTTPS_PROXY \
    no_proxy=$NO_PROXY
WORKDIR /workspace
COPY . .
RUN --mount=type=cache,id=private-reader-gradle,target=/root/.gradle,sharing=locked \
    sed -i 's/\r$//' ./gradlew \
    && chmod +x ./gradlew \
    && if [ -n "$GRADLE_PROXY_HOST" ] && [ -n "$GRADLE_PROXY_PORT" ]; then \
         export GRADLE_OPTS="-Dhttp.proxyHost=$GRADLE_PROXY_HOST -Dhttp.proxyPort=$GRADLE_PROXY_PORT -Dhttps.proxyHost=$GRADLE_PROXY_HOST -Dhttps.proxyPort=$GRADLE_PROXY_PORT ${GRADLE_OPTS:-}"; \
       fi \
    && ./gradlew :app:bootJar --no-daemon --build-cache \
    && boot_jar="$(find app/build/libs -maxdepth 1 -type f -name '*.jar' ! -name '*-plain.jar' -print -quit)" \
    && test -n "$boot_jar" \
    && cp "$boot_jar" /tmp/app.jar

FROM eclipse-temurin:21-jre@sha256:ff65ff0d43c73d2b675eb4b758665a5cb487e7df127436a9979f8172c144c819
WORKDIR /app
COPY --from=builder /tmp/app.jar app.jar
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
