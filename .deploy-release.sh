#!/usr/bin/env bash
set -euo pipefail

release="$(readlink -f /opt/private-reader/current)"
jar_upload="/tmp/private-reader.jar"
web_upload="/tmp/private-reader-web.tar.gz"
web_staging="$release/web.staging"

test -n "$release"
case "$release" in
  /opt/private-reader/releases/*) ;;
  *) printf 'unexpected release path: %s\n' "$release" >&2; exit 1 ;;
esac
test -f "$jar_upload"
test -f "$web_upload"

docker rm -f private-reader-backend-next private-reader-backend-old >/dev/null 2>&1 || true
docker ps -aq --filter 'name=^/private-reader-backend-rollback-' | xargs -r docker rm -f >/dev/null
docker rm -f private-reader-backend >/dev/null 2>&1 || true

install -o root -g root -m 0644 "$jar_upload" "$release/app.jar"
rm -rf "$web_staging"
mkdir -p "$web_staging"
tar -xzf "$web_upload" -C "$web_staging"
rm -rf "$release/web"
mv "$web_staging" "$release/web"
chown -R root:root "$release"
rm -f "$jar_upload" "$web_upload"

docker run -d \
  --name private-reader-backend \
  --network private-reader \
  --env-file /opt/private-reader/secrets/backend.env \
  --env 'JAVA_TOOL_OPTIONS=-XX:MaxRAMPercentage=65 -XX:+UseSerialGC' \
  --memory 768m \
  --memory-swap 1280m \
  --restart unless-stopped \
  -p 18080:8080 \
  -v "$release/app.jar:/app/app.jar:ro" \
  -v /opt/private-reader/storage:/app/storage \
  eclipse-temurin:21-jre \
  java -jar /app/app.jar >/dev/null

for _ in $(seq 1 90); do
  if curl -fsS http://127.0.0.1:18080/actuator/health | grep -q '"status":"UP"'; then
    printf 'release=%s\n' "$release"
    printf 'backend_health='
    curl -fsS http://127.0.0.1:18080/actuator/health
    printf '\n'
    exit 0
  fi
  sleep 1
done

docker logs --tail 120 private-reader-backend >&2 || true
exit 1
