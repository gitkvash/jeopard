<#
    Reloads the question set.

    PilotSeeder only seeds when the clue table is empty, so a database that has
    already been seeded ignores a changed pilot.json. This empties the content
    tables (and the games that reference them) so the next backend start reads
    the file again.

    Games are deleted too, and they have to be: a game row points at a round and
    a clue, so content cannot be replaced underneath one. Anything in progress
    is lost -- that is the point of running this.

    Usage:
        .\reseed.ps1            # ask first
        .\reseed.ps1 -Force     # do not ask
#>
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$container = 'jeopard-db'

$running = docker ps --filter "name=$container" --filter 'status=running' --format '{{.Names}}'
if ($running -notcontains $container) {
    Write-Host "starting Postgres..." -ForegroundColor Cyan
    Push-Location (Split-Path $PSScriptRoot -Parent)
    try { docker compose up -d | Out-Null } finally { Pop-Location }
}

# Show what is there now, so the count that disappears is not a surprise.
$before = docker exec $container psql -U jeopard -d jeopard -tAc `
    "SELECT (SELECT count(*) FROM package) || ' packages, ' || (SELECT count(*) FROM clue) || ' clues, ' || (SELECT count(*) FROM game) || ' games'"
Write-Host "currently seeded: $before" -ForegroundColor DarkGray

if (-not $Force) {
    $answer = Read-Host 'Delete all content and all games? [y/N]'
    if ($answer -ne 'y' -and $answer -ne 'Y') {
        Write-Host 'cancelled' -ForegroundColor Yellow
        return
    }
}

# Order matters only in that game rows reference clue and round; TRUNCATE with
# CASCADE takes the dependent game tables with it.
docker exec $container psql -U jeopard -d jeopard -c `
    "TRUNCATE clue, topic, round, package, game RESTART IDENTITY CASCADE;" | Out-Null

$after = docker exec $container psql -U jeopard -d jeopard -tAc `
    "SELECT (SELECT count(*) FROM package) || ' packages, ' || (SELECT count(*) FROM clue) || ' clues'"
Write-Host "content cleared: $after" -ForegroundColor Green
Write-Host 'start the backend to seed the new set:  .\backend\run.ps1' -ForegroundColor Cyan
