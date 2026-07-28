$ErrorActionPreference = 'Stop'

Write-Host "Starting PostgreSQL via Docker Compose..."
docker compose up -d postgres

Write-Host "Done."

