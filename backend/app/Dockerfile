FROM eclipse-temurin:21-jdk AS builder
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY
ENV HTTP_PROXY=$HTTP_PROXY \
    HTTPS_PROXY=$HTTPS_PROXY \
    NO_PROXY=$NO_PROXY \
    http_proxy=$HTTP_PROXY \
    https_proxy=$HTTPS_PROXY \
    no_proxy=$NO_PROXY
WORKDIR /workspace
COPY . .
RUN sed -i 's/\r$//' ./gradlew \
    && chmod +x ./gradlew \
    && ./gradlew :app:bootJar --no-daemon \
    && boot_jar="$(find app/build/libs -maxdepth 1 -type f -name '*.jar' ! -name '*-plain.jar' -print -quit)" \
    && test -n "$boot_jar" \
    && cp "$boot_jar" /tmp/app.jar

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=builder /tmp/app.jar app.jar
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
