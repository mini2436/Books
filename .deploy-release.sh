#!/usr/bin/env bash
set -euo pipefail

release="/opt/private-reader/releases/20260728-bf54712"
old_release="$(readlink -f /opt/private-reader/current)"
jar_upload="/tmp/private-reader-bf54712.jar"
web_upload="/tmp/private-reader-web-bf54712.tar.gz"

mkdir -p "$release/web"
install -o root -g root -m 0644 "$jar_upload" "$release/app.jar"
tar -xzf "$web_upload" -C "$release/web"
chown -R root:root "$release"
rm -f "$jar_upload" "$web_upload"

run_backend() {
  local name="$1"
  local host_port="$2"
  local restart_policy="$3"
  docker run -d \
    --name "$name" \
    --network private-reader \
    --env-file /opt/private-reader/secrets/backend.env \
    --env 'JAVA_TOOL_OPTIONS=-XX:MaxRAMPercentage=65 -XX:+UseSerialGC' \
    --memory 768m \
    --memory-swap 1280m \
    --restart "$restart_policy" \
    -p "${host_port}:8080" \
    -v "$release/app.jar:/app/app.jar:ro" \
    -v /opt/private-reader/storage:/app/storage \
    eclipse-temurin:21-jre \
    java -jar /app/app.jar
}

wait_for_health() {
  local port="$1"
  for _ in $(seq 1 90); do
    if curl -fsS "http://127.0.0.1:${port}/actuator/health" | grep -q '"status":"UP"'; then
      return 0
    fi
    sleep 1
  done
  return 1
}

docker rm -f private-reader-backend-next >/dev/null 2>&1 || true
run_backend private-reader-backend-next 18081 no >/dev/null
if ! wait_for_health 18081; then
  docker logs --tail 120 private-reader-backend-next >&2 || true
  docker rm -f private-reader-backend-next >/dev/null 2>&1 || true
  exit 1
fi
docker rm -f private-reader-backend-next >/dev/null

docker rm -f private-reader-backend-old >/dev/null 2>&1 || true
docker stop private-reader-backend >/dev/null
docker rename private-reader-backend private-reader-backend-old

ln -sfn "$release" /opt/private-reader/current.next
mv -Tf /opt/private-reader/current.next /opt/private-reader/current

rollback() {
  docker rm -f private-reader-backend >/dev/null 2>&1 || true
  ln -sfn "$old_release" /opt/private-reader/current.next
  mv -Tf /opt/private-reader/current.next /opt/private-reader/current
  docker rename private-reader-backend-old private-reader-backend
  docker start private-reader-backend >/dev/null
}

if ! run_backend private-reader-backend 18080 unless-stopped >/dev/null; then
  rollback
  exit 1
fi
if ! wait_for_health 18080; then
  docker logs --tail 120 private-reader-backend >&2 || true
  rollback
  exit 1
fi

docker rm -f private-reader-backend-old >/dev/null
printf 'release=%s\n' "$(readlink -f /opt/private-reader/current)"
printf 'backend_health='
curl -fsS http://127.0.0.1:18080/actuator/health
printf '\n'
