$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$nodeHome = 'C:\Users\mini2436\Tools\node-v20.19.5-win-x64'
$env:PATH = "$nodeHome;$env:PATH"

Write-Host "Installing frontend dependencies..."
Push-Location (Join-Path $projectRoot 'web')
try {
    npm install
    npm run build
}
finally {
    Pop-Location
}
