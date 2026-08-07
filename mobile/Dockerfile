# syntax=docker/dockerfile:1.7

FROM --platform=$BUILDPLATFORM ghcr.io/cirruslabs/flutter:3.41.6 AS builder
ARG API_BASE_URL=/
WORKDIR /workspace
COPY . .
RUN flutter pub get \
    && flutter build web --release --no-web-resources-cdn --dart-define=API_BASE_URL="$API_BASE_URL"

FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /workspace/build/web /usr/share/nginx/html
EXPOSE 80
