<#
    Starts the Jeopard backend.

    Exists because there is no JDK on PATH on this machine (the JDKs live under
    ~/.jdks, managed by IntelliJ) and because `spring-boot:run` forks a child
    JVM that outlives Ctrl-C, so port 8080 tends to stay occupied.

    Usage:
        .\run.ps1              # start
        .\run.ps1 -Stop        # just free port 8080
        .\run.ps1 -Test        # run the test suite instead
#>
param(
    [switch]$Stop,
    [switch]$Test
)

$ErrorActionPreference = 'Stop'

# Spring Boot 4 needs Java 17+; this is the newest LTS present.
$jdk = Join-Path $env:USERPROFILE '.jdks\ms-21.0.11'
if (-not (Test-Path $jdk)) {
    $jdk = Get-ChildItem (Join-Path $env:USERPROFILE '.jdks') -Directory |
            Where-Object { $_.Name -match '^(ms|openjdk)-(2[1-9]|[3-9][0-9])' } |
            Sort-Object Name -Descending |
            Select-Object -First 1 -ExpandProperty FullName
}
if (-not $jdk) { throw 'No JDK 21+ found under ~/.jdks' }
$env:JAVA_HOME = $jdk
Write-Host "JAVA_HOME = $jdk" -ForegroundColor DarkGray

# Free the port -- a previous forked JVM is usually still holding it.
$listeners = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue
foreach ($l in $listeners) {
    Write-Host "stopping process $($l.OwningProcess) on port 8080" -ForegroundColor Yellow
    Stop-Process -Id $l.OwningProcess -Force -ErrorAction SilentlyContinue
}
if ($Stop) { return }

# Maven finds the POM by working directory, so run it from backend/ no matter
# where the script was called from -- the README invokes it from the repository root.
if ($Test) {
    Push-Location $PSScriptRoot
    try { & (Join-Path $PSScriptRoot 'mvnw.cmd') -B -ntp test } finally { Pop-Location }
    return
}

# Postgres runs in Docker on 5433 (5432 is taken by the native PostgreSQL 18
# service on this machine).
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $running = docker compose ps --status running --services 2>$null
    if ($running -notcontains 'db') {
        Write-Host 'starting Postgres...' -ForegroundColor Cyan
        docker compose up -d | Out-Null
    }
} finally {
    Pop-Location
}

Push-Location $PSScriptRoot
try {
    & (Join-Path $PSScriptRoot 'mvnw.cmd') -B -ntp spring-boot:run
} finally {
    Pop-Location
}
