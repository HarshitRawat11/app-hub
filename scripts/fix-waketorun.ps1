<#
.SYNOPSIS
  Actually enable the nightly teardown's wake timer. Run ELEVATED.

.WHY
  Written 2026-09-28, after reading the task's own definition for the first
  time. D-25 was closed on 2026-09-22 believing `-WakeToRun` had been applied.
  It had not:

      WakeToRun : False        (CIM object AND the exported XML)

  And the power policy that gates it reads 0x1 on both AC and DC, which is
  "Important Wake Timers Only" -- NOT "Enable". A Task Scheduler wake is not an
  important wake timer; Windows reserves that for system-critical work. So the
  task could not wake this machine by either mechanism.

  THAT IS PROBABLY D-31. The 2026-09-21 23:30 run produced no event and then
  caught up four hours later; `StartWhenAvailable: True` defers rather than
  misses, which is why NumberOfMissedRuns reads 0. A machine in modern standby
  at 23:30, with no working wake timer, behaves exactly like that.

  It also means the 2026-09-20 wake at 23:30:38 -- which D-25 was closed on --
  was NOT this task waking the machine. Something else woke it and the task ran
  on arrival. Right outcome, wrong mechanism, and the wrong mechanism does not
  repeat reliably.

.WHAT THIS DOES
  1. Sets WakeToRun = True on the working task.
  2. Sets the "Allow wake timers" policy to Enable (index 2) on AC and DC.
  3. Reads both back and FAILS LOUDLY if either did not take -- because the
     original claim failed precisely by not being read back.

.HOW TO RUN
  Elevated PowerShell:
    powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\harshit.rawat\Documents\Projects\app-hub\scripts\fix-waketorun.ps1"
#>

$ErrorActionPreference = 'Continue'
$task = "app-hub nightly teardown (harshit.rawat)"

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "NOT ELEVATED. Re-run as administrator." -ForegroundColor Red
    exit 1
}

# --- 1. the task setting ---------------------------------------------------
Write-Host "[1/3] Setting WakeToRun on '$task'..." -ForegroundColor Cyan
$t = Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
if (-not $t) { Write-Host "  TASK NOT FOUND. Nothing done." -ForegroundColor Red; exit 1 }
Write-Host ("      before: WakeToRun = {0}" -f $t.Settings.WakeToRun)
$t.Settings.WakeToRun = $true
Set-ScheduledTask -TaskName $task -Settings $t.Settings | Out-Null

# --- 2. the power policy that gates it -------------------------------------
# Index 2 = Enable. Index 1 = Important Wake Timers Only, which does NOT cover
# a Task Scheduler wake and is what this machine was set to.
Write-Host "[2/3] Setting 'Allow wake timers' to Enable on AC and DC..." -ForegroundColor Cyan
powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP RTCWAKE 2
powercfg /setdcvalueindex SCHEME_CURRENT SUB_SLEEP RTCWAKE 2
powercfg /setactive SCHEME_CURRENT

# --- 3. READ IT BACK. This is the whole point. -----------------------------
# D-25's original claim rested on a script reporting success. Reporting success
# and having taken effect are different facts, and this is the difference.
Write-Host "[3/3] Verifying both actually took..." -ForegroundColor Cyan
$after = (Get-ScheduledTask -TaskName $task).Settings.WakeToRun
Write-Host ("      WakeToRun now = {0}" -f $after)

$q  = powercfg /query SCHEME_CURRENT SUB_SLEEP RTCWAKE
$ac = ($q | Select-String 'Current AC Power Setting Index') -replace '.*:\s*',''
$dc = ($q | Select-String 'Current DC Power Setting Index') -replace '.*:\s*',''
Write-Host ("      wake timers  AC={0}  DC={1}   (want 0x00000002 on both)" -f $ac.Trim(), $dc.Trim())

$ok = $true
if ($after -ne $true)            { Write-Host "  FAILED: WakeToRun did not stick" -ForegroundColor Red; $ok = $false }
if ($ac.Trim() -ne '0x00000002') { Write-Host "  FAILED: AC wake timers not Enabled" -ForegroundColor Red; $ok = $false }
if ($dc.Trim() -ne '0x00000002') { Write-Host "  FAILED: DC wake timers not Enabled" -ForegroundColor Red; $ok = $false }

if ($ok) {
    Write-Host ""
    Write-Host "Both took. The teardown can now wake this machine at 23:30." -ForegroundColor Green
    Write-Host "STILL NOT PROVEN, and only one thing proves it: a night where the" -ForegroundColor Yellow
    Write-Host "laptop sleeps before 23:30 and a Power-Troubleshooter wake event" -ForegroundColor Yellow
    Write-Host "appears AT 23:30 naming the task. Settings taking effect is not the" -ForegroundColor Yellow
    Write-Host "same fact as the wake happening -- that is how D-25 went wrong." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "Something did not take. Do NOT record this as fixed." -ForegroundColor Red
    exit 1
}
