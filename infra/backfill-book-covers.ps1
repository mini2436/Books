param(
    [switch]$Overwrite,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$backendRoot = Join-Path $repoRoot 'backend'

if (-not $SkipBuild) {
    $javaVersionOutput = (& java -version 2>&1 | Out-String)
    if ($javaVersionOutput -notmatch 'version "21(?:\.|\")') {
        $androidStudioJdk = 'C:\Program Files\Android\Android Studio\jbr'
        if (-not (Test-Path (Join-Path $androidStudioJdk 'bin\java.exe'))) {
            throw 'JDK 21 is required. Set JAVA_HOME to JDK 21 or install Android Studio.'
        }
        $env:JAVA_HOME = $androidStudioJdk
        $env:Path = "$(Join-Path $androidStudioJdk 'bin');$env:Path"
    }

    Push-Location $backendRoot
    try {
        & .\gradlew.bat :app:bootJar
        if ($LASTEXITCODE -ne 0) {
            throw "Backend build failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

Push-Location $repoRoot
try {
    & docker compose up -d postgres redis rabbitmq
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to start Docker dependencies with exit code $LASTEXITCODE"
    }

    $dockerArguments = @(
        'compose', 'run', '--rm',
        '-e', 'APP_BACKFILL_BOOK_COVERS=true'
    )
    if ($Overwrite) {
        $dockerArguments += @('-e', 'APP_BACKFILL_BOOK_COVERS_OVERWRITE=true')
    }
    $dockerArguments += 'backend'

    & docker @dockerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Cover backfill failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}
