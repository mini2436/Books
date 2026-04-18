$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$schema = Join-Path $projectRoot 'infra\database\001_schema.sql'
$seed = Join-Path $projectRoot 'infra\database\010_seed_dev.sql'

Write-Host "Apply schema with a PostgreSQL client, for example:"
Write-Host "psql -h localhost -U reader -d private_reader -f `"$schema`""
Write-Host "Optional dev seed:"
Write-Host "psql -h localhost -U reader -d private_reader -f `"$seed`""

