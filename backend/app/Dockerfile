FROM eclipse-temurin:21-jdk AS builder
WORKDIR /workspace
COPY .. .
RUN ./gradlew :app:bootJar --no-daemon

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=builder /workspace/app/build/libs/app-0.1.0.jar app.jar
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
