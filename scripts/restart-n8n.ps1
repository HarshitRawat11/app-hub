<#
.SYNOPSIS
    Restart the n8n container so its schedule triggers re-register. Fixes D-24.

.DESCRIPTION
    THE DEFECT THIS EXISTS FOR.

    n8n registers its Schedule Triggers as in-process timers when a workflow is
    activated. Those timers do not survive the host being suspended: Docker
    Desktop's VM is paused with Windows, and on resume n8n is running, healthy,
    reporting `active: true` for every workflow -- and firing nothing, ever
    again, until it is restarted.

    Measured rather than inferred. `eks-cost-watchdog` fired on schedule at
    2026-09-14 21:00:05 IST, the machine slept that night, and over the next
    four days it missed SIX firings while reporting active the whole time. On
    2026-09-18 a cluster was left running by a half-finished teardown; the
    watchdog should have emailed at 17:00 and again at 21:00 and emailed
    neither. That cost about $0.80 and would have cost more overnight.

    So: restart n8n whenever the machine wakes, and once a day before the 17:00
    trigger as a belt-and-braces. A restart is about ten seconds and costs
    nothing.

    WHAT THIS DOES NOT DO, stated plainly: it does not prove the crons fired.
    `active: true` is exactly what n8n reported throughout the four dead days,
    so reading it back would be worthless. The only honest evidence is an
    execution row appearing after a trigger time -- see VERIFY below.

.NOTES
    Registered by scripts/register-n8n-wake-task.ps1.
    Logs to logs/restart-n8n-<timestamp>.log (gitignored).
#>

[CmdletBinding()]
param(
    [string]$ContainerName = 'n8n',
    # After a resume, Docker Desktop is not immediately back. Wait for the
    # daemon rather than failing on the first try -- this script's whole job is
    # to run at the least convenient moment.
    [int]$DockerWaitSeconds = 300
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $repo 'logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$log = Join-Path $logDir ("restart-n8n-{0}.log" -f (Get-Date -Format 'yyyy-MM-dd_HHmmss'))

function Say($msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Write-Host $line
    Add-Content -Path $log -Value $line -Encoding utf8
}

Say "=== restart-n8n (D-24) ==="
Say "user      : $env:USERNAME"
Say "container : $ContainerName"
Say "trigger   : $(if ($env:N8N_RESTART_REASON) { $env:N8N_RESTART_REASON } else { 'manual or scheduled' })"

# Resolve docker.exe explicitly. A scheduled task does not inherit an
# interactive shell's PATH, so a bare `docker` can be "not recognised" here
# while working perfectly in a terminal -- which would make this script fail
# only when it matters and only unattended.
$docker = (Get-Command docker.exe -ErrorAction SilentlyContinue).Source
if (-not $docker) {
    foreach ($p in @(
        "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe",
        "$env:ProgramW6432\Docker\Docker\resources\bin\docker.exe"
    )) { if (Test-Path $p) { $docker = $p; break } }
}
if (-not $docker) {
    Say "FAIL: docker.exe not found on PATH or in the usual install locations."
    exit 1
}
Say "docker    : $docker"

# Wait for the daemon. `docker info` is the honest check -- `docker ps` can
# succeed against a half-started daemon.
$deadline = (Get-Date).AddSeconds($DockerWaitSeconds)
$ready = $false
while ((Get-Date) -lt $deadline) {
    & $docker info --format '{{.ServerVersion}}' 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Seconds 10
}
if (-not $ready) {
    Say "FAIL: Docker daemon did not become ready within $DockerWaitSeconds s."
    Say "      n8n was NOT restarted. Its crons are probably still dead."
    exit 1
}
Say "docker daemon ready"

# Is the container even there? "absent" and "stopped" are different problems
# and deserve different messages.
$state = (& $docker inspect $ContainerName --format '{{.State.Status}}' 2>$null)
if ($LASTEXITCODE -ne 0) {
    Say "FAIL: container '$ContainerName' does not exist. Nothing to restart."
    exit 1
}
Say "state before: $state"

& $docker restart $ContainerName | Out-Null
if ($LASTEXITCODE -ne 0) {
    Say "FAIL: docker restart returned $LASTEXITCODE"
    exit 1
}

# Wait for n8n to answer, not just for the container to be 'running'. The
# container is 'running' seconds before n8n has finished booting, and a script
# that reports success at that point is reporting the wrong thing.
$up = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 5
    try {
        $r = Invoke-WebRequest -Uri 'http://localhost:5678/healthz' -UseBasicParsing -TimeoutSec 5
        if ($r.StatusCode -eq 200) { $up = $true; break }
    } catch { }
}

$after = (& $docker inspect $ContainerName --format '{{.State.Status}}' 2>$null)
Say "state after : $after"

if ($up) {
    Say "n8n answered on :5678 -- restart complete"
} else {
    Say "WARNING: container is '$after' but n8n did not answer on :5678 within 150s."
    Say "         Check: docker logs $ContainerName --tail 50"
}

Say ""
Say "NOTE: this does NOT prove the schedule triggers fire. n8n reported"
Say "      active: true throughout the four days it fired nothing (D-24)."
Say "      The only real evidence is an execution row after a trigger time:"
Say "        cost-watchdog fires at 17:00 and 21:00 IST."
Say "=== done ==="

if ($up) { exit 0 } else { exit 1 }
