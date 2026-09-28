<#
.SYNOPSIS
  Everything in app-hub that needs Windows admin rights. Run ONCE, elevated.

.WHY THIS EXISTS
  Written 2026-09-28, when the owner had admin rights temporarily and expected
  to lose them. Two of the three things below are NOT installs -- they are
  DIAGNOSTIC CAPTURES that become impossible without elevation. A scheduled
  task's history and definition are unreadable unelevated: `schtasks /query`
  answers "Access is denied" while an invented name answers "cannot find", so
  the task provably exists and provably cannot be read. If admin goes away
  before this runs, D-31 becomes permanently undiagnosable.

.HOW TO RUN
  Right-click PowerShell -> Run as administrator, then:
    cd C:\Users\harshit.rawat\Documents\Projects\app-hub
    .\scripts\admin-window.ps1

  It is safe to re-run. Nothing here destroys data except step 3, which deletes
  a task that has never run and is named explicitly.
#>

$ErrorActionPreference = 'Continue'
$repo    = Split-Path -Parent $PSScriptRoot
$outDir  = Join-Path $repo 'logs'
$stamp   = Get-Date -Format 'yyyy-MM-dd_HHmmss'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "NOT ELEVATED. Nothing below will work. Re-run as administrator." -ForegroundColor Red
    exit 1
}
Write-Host "Elevated. Proceeding." -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------------------------
# 1. CAPTURE D-31 EVIDENCE FIRST.
#
# Do this BEFORE anything else, because it is the only item here that cannot be
# redone later. On 2026-09-21 the 23:30 teardown produced no Task Scheduler
# event at all while the machine was awake, then caught up four hours late. The
# cause is UNKNOWN and the task's own history is the one source that can say.
# ---------------------------------------------------------------------------
Write-Host "[1/4] Capturing scheduled-task evidence for D-31..." -ForegroundColor Cyan
$task = "app-hub nightly teardown (harshit.rawat)"
$d31  = Join-Path $outDir "d31-task-evidence-$stamp.txt"

"=== Get-ScheduledTaskInfo ===" | Out-File $d31 -Encoding utf8
Get-ScheduledTaskInfo -TaskName $task -ErrorAction SilentlyContinue |
    Format-List * | Out-File $d31 -Append -Encoding utf8

"`n=== Task definition (settings: battery, wake, restart policy) ===" | Out-File $d31 -Append -Encoding utf8
(Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue).Settings |
    Format-List * | Out-File $d31 -Append -Encoding utf8

"`n=== Triggers ===" | Out-File $d31 -Append -Encoding utf8
(Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue).Triggers |
    Format-List * | Out-File $d31 -Append -Encoding utf8

"`n=== Full XML ===" | Out-File $d31 -Append -Encoding utf8
schtasks /query /TN $task /XML 2>&1 | Out-File $d31 -Append -Encoding utf8

"`n=== Wake-timer power policy (AC and DC) ===" | Out-File $d31 -Append -Encoding utf8
powercfg /query SCHEME_CURRENT SUB_SLEEP RTCWAKE 2>&1 | Out-File $d31 -Append -Encoding utf8

Write-Host "      -> $d31"

# ---------------------------------------------------------------------------
# 2. INSTALL TAILSCALE.
#
# The only genuine install. It closes G1's remaining half -- the tailnet
# currently holds exactly ONE device, the app-hub container, so tailnet-only
# serving reaches nobody -- and it is what lets the two LOOPBACK PUBLISHES be
# removed again (gateway 127.0.0.1:8001 and n8n 127.0.0.1:5678 both exist only
# because there is no second tailnet device).
#
# Signing in does NOT need admin, so it can be done later. The install does.
# ---------------------------------------------------------------------------
Write-Host "[2/4] Installing Tailscale..." -ForegroundColor Cyan
if (Get-Command tailscale -ErrorAction SilentlyContinue) {
    Write-Host "      already installed, skipping"
} elseif (Test-Path "C:\Program Files\Tailscale\tailscale.exe") {
    Write-Host "      already installed, skipping"
} else {
    winget install --id Tailscale.Tailscale --exact --accept-source-agreements --accept-package-agreements
}

# ---------------------------------------------------------------------------
# 3. REMOVE THE DEAD TASK (D-32).
#
# A bare "app-hub nightly teardown" is registered to run as UZIO\uzio.admin, an
# account that never logs in, so it emits id=332 "will not be run" at every
# trigger and has NEVER run. It costs nothing, but its failure-shaped events sit
# in the same log as the real task's successes and cost twenty minutes of the
# D-25 investigation.
#
# THE BARE NAME ONLY. "app-hub nightly teardown (harshit.rawat)" is the WORKING
# task and must survive -- the two differ by a suffix, which is the same
# near-identical-names trap that deleted an ArgoCD deploy key on 2026-09-20.
# ---------------------------------------------------------------------------
Write-Host "[3/4] Removing the dead duplicate task (D-32)..." -ForegroundColor Cyan
$bare = "app-hub nightly teardown"
schtasks /delete /TN $bare /F 2>&1 | ForEach-Object { Write-Host "      $_" }

# ---------------------------------------------------------------------------
# 4. PROVE THE WORKING TASK SURVIVED.
#
# Never finish a delete without checking what is left.
# ---------------------------------------------------------------------------
Write-Host "[4/4] Verifying the WORKING task still exists..." -ForegroundColor Cyan
$still = Get-ScheduledTask -TaskName "app-hub*" -ErrorAction SilentlyContinue
if ($still) {
    $still | ForEach-Object { Write-Host ("      {0}{1}  state={2}" -f $_.TaskPath, $_.TaskName, $_.State) }
} else {
    Write-Host "      NOTHING FOUND -- investigate before trusting tonight's teardown" -ForegroundColor Red
}

Write-Host ""
Write-Host "Done. Still to do WITHOUT admin:" -ForegroundColor Green
Write-Host "  - sign in to Tailscale with the SAME account that owns tailnet tailf4b0ae"
Write-Host "  - do NOT tag this device; tag:app-hub is for the container"
Write-Host "  - then: tailscale status  should show TWO devices"
Write-Host "  - and:  app-hub.tailf4b0ae.ts.net must resolve to 100.x, not 209.177.x"
