<#
.SYNOPSIS
    Register a Scheduled Task that restarts n8n on wake and daily. Fixes D-24.

.DESCRIPTION
    TWO TRIGGERS, because one of them is not reliable enough on its own.

    1. ON RESUME FROM SLEEP -- the actual root cause. n8n's Schedule Trigger
       timers do not survive the Docker VM being suspended, so the moment the
       machine wakes is exactly when a restart is needed. Windows raises
       Microsoft-Windows-Power-Troubleshooter event 1 on resume; verified
       present on this machine (four entries across three days, matching the
       real sleep periods).

    2. DAILY AT 16:45 -- a belt-and-braces, forty-five minutes before
       cost-watchdog's 17:00 trigger. Modern-standby machines do not always
       raise the resume event, and a monitor whose repair depends on an event
       that "usually" fires is a monitor that usually works. A container
       restart is ten seconds; running it once a day it was not needed is free.

    ELEVATION. Registering a task that runs as you does not require admin. But
    the existing 'app-hub nightly teardown' task was created elevated and is
    unreadable without it, so if that pattern repeats here, re-run this from an
    elevated shell.

.NOTES
    Action: scripts/restart-n8n.ps1
    Undo:   Unregister-ScheduledTask -TaskName "app-hub restart n8n" -Confirm:$false
#>

[CmdletBinding()]
param(
    [string]$TaskName = 'app-hub restart n8n',
    [string]$DailyAt  = '16:45'
)

$ErrorActionPreference = 'Stop'
$repo   = Split-Path -Parent $PSScriptRoot
$action = Join-Path $repo 'scripts\restart-n8n.ps1'

if (-not (Test-Path $action)) { Write-Host "ERROR: $action not found."; exit 1 }

Write-Host "Repo   : $repo"
Write-Host "Action : $action"
Write-Host "Daily  : $DailyAt   (plus: on every resume from sleep)"
Write-Host ""

$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $elevated) {
    Write-Host "Not elevated. Continuing -- a task that runs as YOU needs no admin."
    Write-Host "If this fails with 0x800700b7 ('Cannot create a file when that file"
    Write-Host "already exists'), that is a PERMISSIONS error wearing a filesystem"
    Write-Host "error's clothes: the task exists under another principal. Re-run"
    Write-Host "this from an elevated PowerShell."
    Write-Host ""
}

# Remove any previous copy so this script is idempotent. Guarded, because
# Get-ScheduledTask returns nothing for a task you cannot read -- so a silent
# "not found" here does not mean absent (CLAUDE.md section 9).
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Removing the existing '$TaskName' first."
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

$psExe = (Get-Command powershell.exe).Source
$act = New-ScheduledTaskAction -Execute $psExe `
    -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $action)

# Trigger 1: the daily safety net.
$daily = New-ScheduledTaskTrigger -Daily -At $DailyAt

# Trigger 2: on resume. There is no -OnResume switch, so this is built from the
# event subscription directly -- System log, Power-Troubleshooter, EventID 1.
$cimClass = Get-CimClass -Namespace ROOT\Microsoft\Windows\TaskScheduler -ClassName MSFT_TaskEventTrigger
$wake = New-CimInstance -CimClass $cimClass -ClientOnly
$wake.Enabled = $true
$wake.Subscription = @'
<QueryList><Query Id="0" Path="System"><Select Path="System">*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]</Select></Query></QueryList>
'@
# Docker Desktop is not back the instant Windows is. The action script waits for
# the daemon too, but delaying here keeps the log honest about what happened.
$wake.Delay = 'PT2M'

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 15)

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $act `
    -Trigger @($daily, $wake) `
    -Settings $settings `
    -Description "Restarts the n8n container so its Schedule Triggers re-register after the host sleeps (D-24). See scripts/restart-n8n.ps1." | Out-Null

# VERIFY, rather than announcing success because nothing threw.
$check = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $check) {
    Write-Host ""
    Write-Host "REGISTERED, BUT NOT READABLE BACK." -ForegroundColor Red
    Write-Host "It is owned by another principal. Do not trust it -- re-run elevated."
    exit 1
}

Write-Host ""
Write-Host "Registered '$TaskName'."
Write-Host "  runs as  : $($check.Principal.UserId)"
Write-Host "  triggers : $($check.Triggers.Count)  (expect 2: daily + on-resume)"
Write-Host "  battery  : start=$(-not $check.Settings.DisallowStartIfOnBatteries) keep-running=$(-not $check.Settings.StopIfGoingOnBatteries)"

if ($check.Triggers.Count -lt 2) {
    Write-Host ""
    Write-Host "WARNING: fewer than 2 triggers registered." -ForegroundColor Red
    Write-Host "The on-resume event trigger is the one that fixes D-24; the daily"
    Write-Host "run alone leaves the watchdog dead between waking and 16:45."
    exit 1
}

if ($check.Settings.DisallowStartIfOnBatteries -or $check.Settings.StopIfGoingOnBatteries) {
    Write-Host ""
    Write-Host "WARNING: this will not run on battery power." -ForegroundColor Red
    Write-Host "It would sit in state 'Queued' producing no output and no error --"
    Write-Host "on exactly the occasions a laptop wakes unplugged."
    exit 1
}

Write-Host ""
Write-Host "Test it now, without waiting for a sleep:"
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'"
Write-Host ""
Write-Host "IT IS NOT PROVEN UNTIL AN EXECUTION ROW APPEARS. n8n reported"
Write-Host "active: true throughout the four days it fired nothing. Leave the"
Write-Host "machine to sleep, then check that cost-watchdog has an execution at"
Write-Host "17:00 or 21:00 IST."
