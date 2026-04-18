$ErrorActionPreference = 'Stop'

Write-Host "Starting PostgreSQL, Redis, and RabbitMQ via Docker Compose..."
docker compose up -d postgres redis rabbitmq

Write-Host "Done."

