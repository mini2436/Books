FROM eclipse-temurin:21-jdk AS builder
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY
ARG PROXY_HOST=host.docker.internal
ARG PROXY_PORT=10808
ENV HTTP_PROXY=$HTTP_PROXY \
    HTTPS_PROXY=$HTTPS_PROXY \
    NO_PROXY=$NO_PROXY \
    http_proxy=$HTTP_PROXY \
    https_proxy=$HTTPS_PROXY \
    no_proxy=$NO_PROXY \
    GRADLE_OPTS="-Dhttp.proxyHost=${PROXY_HOST} -Dhttp.proxyPort=${PROXY_PORT} -Dhttps.proxyHost=${PROXY_HOST} -Dhttps.proxyPort=${PROXY_PORT}" \
    JAVA_TOOL_OPTIONS="-Dhttp.proxyHost=${PROXY_HOST} -Dhttp.proxyPort=${PROXY_PORT} -Dhttps.proxyHost=${PROXY_HOST} -Dhttps.proxyPort=${PROXY_PORT}"
WORKDIR /workspace
COPY . .
RUN sed -i 's/\r$//' ./gradlew && chmod +x ./gradlew && ./gradlew :app:bootJar --no-daemon && cp app/build/libs/*.jar /tmp/app.jar

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=builder /tmp/app.jar app.jar
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
