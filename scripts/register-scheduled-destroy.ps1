# Registers the nightly teardown as a Windows Scheduled Task.
#
# WHY THIS IS A SEPARATE SCRIPT RATHER THAN SOMETHING CLAUDE RAN FOR YOU:
# it registers an unattended `terraform destroy`. Two things about that are
# yours to decide, not mine -- the time it fires, and whether you are
# comfortable with a destroy running while you might still be working. So this
# prepares it and you run it.
#
# WHAT IT DOES
# Runs scripts/scheduled-destroy.sh through WSL at a fixed time each day. That
# script runs `make down AUTO=1` -- the same teardown as an interactive
# session, in the same order -- and POSTs the result to the n8n
# destroy-notifier webhook, so you get an email either way.
#
# WHY IT IS SAFE ON AN EMPTY ACCOUNT
# `make down` on an account with no cluster is a no-op that reports "does not
# exist yet" for both ECR repositories and a destroy with nothing to destroy.
# It costs nothing and breaks nothing. So there is no reason to only enable it
# on days you brought the cluster up.
#
# WHY IT MATTERS
# The NAT gateway bills continuously, roughly $0.30/hour for the whole stack.
# A cluster left up over a weekend is about $15. `cost-watchdog` emails you at
# 5 PM and 9 PM if EKS is still running, but an email you are not reading does
# not tear anything down. This does.
#
# RUN IT FROM AN ELEVATED POWERSHELL:
#   powershell -ExecutionPolicy Bypass -File scripts\register-scheduled-destroy.ps1
#
# To remove it:
#   Unregister-ScheduledTask -TaskName "app-hub nightly teardown" -Confirm:$false

param(
    # 23:30 by default -- late enough not to interrupt an evening session,
    # early enough that a forgotten cluster does not bill through the night.
    [string]$Time = "23:30",
    [string]$TaskName = "app-hub nightly teardown"
)

$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $PSScriptRoot
$wslRepo = "/mnt/c" + ($repo -replace "^[A-Za-z]:", "" -replace "\\", "/")
$script = "$wslRepo/scripts/scheduled-destroy.sh"

Write-Host "Repo (Windows): $repo"
Write-Host "Repo (WSL):     $wslRepo"
Write-Host "Will run:       wsl -e bash -lc `"$script`""
Write-Host "Daily at:       $Time"
Write-Host ""

if (-not (Test-Path "$repo\scripts\scheduled-destroy.sh")) {
    throw "scripts/scheduled-destroy.sh not found under $repo"
}

# Elevation: WARN, do not refuse. Revised 2026-09-13 after the first version of
# this guard got the rule wrong.
#
# The rule is not "scheduled tasks need admin". Creating a task that runs as
# YOU, in your own context, generally does not. Reading, replacing or starting
# a task owned by SOMEONE ELSE does.
#
# That distinction is exactly what bit here. A task named "app-hub nightly
# teardown" already exists on this machine and is NOT readable by
# UZIO\harshit.rawat -- `Get-ScheduledTask` enumerates 205 other tasks happily
# but omits this one, while `schtasks /query` says "Access is denied" rather
# than "cannot find the file". Different answers for absent vs. invisible, and
# that difference is the evidence: it exists, owned by another principal,
# almost certainly because the script was elevated once under a different
# admin account.
#
# Why that matters far more than visibility: the task's PRINCIPAL decides who
# `wsl.exe` runs as. A different account means a different WSL home directory,
# which means a different ~/.aws/ -- so `make down` would run at 23:30 with no
# app-hub credentials and fail. Silently, on the night it was needed.
#
# Hence: warn, continue, and VERIFY afterwards (see the end of this file).
# Refusing outright would have blocked the one workable path -- registering
# under a name this user actually owns.
$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$me = [Security.Principal.WindowsIdentity]::GetCurrent().Name

if (-not $elevated) {
    Write-Host ""
    Write-Host "Not elevated. Continuing anyway -- registering a task that runs as YOU" -ForegroundColor Yellow
    Write-Host "does not require admin. Two things to know:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1. If a task of this name already exists and is owned by another"
    Write-Host "     account, this will fail with 'Cannot create a file when that file"
    Write-Host "     already exists' (0x800700b7). That is a PERMISSIONS error wearing a"
    Write-Host "     filesystem error's clothes. Re-run with a name you own:"
    Write-Host "       -TaskName `"app-hub nightly teardown ($env:USERNAME)`""
    Write-Host ""
    Write-Host "  2. To check an existing task without elevation, use schtasks -- it"
    Write-Host "     distinguishes 'Access is denied' (exists, unreadable) from"
    Write-Host "     'cannot find the file specified' (genuinely absent):"
    Write-Host "       schtasks /query /TN `"$TaskName`""
    Write-Host ""
}

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Task '$TaskName' already exists. Removing it first."
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

$action = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-e bash -lc `"$script`""
$trigger = New-ScheduledTaskTrigger -Daily -At $Time

# Run whether or not you are logged in would need stored credentials, so this
# runs as the interactive user. Consequence worth knowing: if the machine is
# off or you are logged out at the trigger time, it does not fire -- and
# StartWhenAvailable is what makes it catch up on the next login instead.
$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -DontStopOnIdleEnd `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 45)

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Description "Tears down the app-hub EKS cluster nightly and reports the result to n8n. See scripts/scheduled-destroy.sh." | Out-Null

# VERIFY, rather than announcing success because no exception was thrown.
#
# The whole reason this section exists: a task can register and still be wrong
# in the one way that matters. What decides whether the nightly teardown works
# is not that the task exists -- it is WHO it runs as, because that determines
# which WSL home directory, and therefore which ~/.aws/ credentials, the
# teardown gets.
$check = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $check) {
    Write-Host ""
    Write-Host "REGISTERED, BUT NOT READABLE BACK." -ForegroundColor Red
    Write-Host "That means it is owned by another principal. Do not trust it --"
    Write-Host "register under a name you own instead:"
    Write-Host "  -TaskName `"app-hub nightly teardown ($env:USERNAME)`""
    exit 1
}

$principal = $check.Principal.UserId
Write-Host ""
Write-Host "Registered '$TaskName'."
Write-Host "  runs as : $principal"
Write-Host "  you are : $me"
# Compare on the bare username rather than splitting DOMAIN\user, because the
# principal can be recorded as "UZIO\harshit.rawat", "harshit.rawat", or a SID
# depending on how it was registered. -notmatch on the escaped short name is
# the form that survives all three.
if ($principal -and ($principal -notmatch [regex]::Escape($env:USERNAME))) {
    Write-Host ""
    Write-Host "WARNING: it runs as a DIFFERENT account than you." -ForegroundColor Red
    Write-Host "wsl.exe launched by that account gets a different home directory, so a"
    Write-Host "different ~/.aws/ -- 'make down' will have no app-hub credentials and"
    Write-Host "will fail at the trigger time. Re-register it as yourself."
}
Write-Host ""
Write-Host "Next run: $((Get-ScheduledTaskInfo -TaskName $TaskName).NextRunTime)"
Write-Host ""
Write-Host "Verify:"
Write-Host "  Get-ScheduledTask -TaskName '$TaskName' | Format-List TaskName,State"
Write-Host ""
Write-Host "Test it now WITHOUT waiting for the trigger (safe on an empty account):"
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'"
Write-Host ""
Write-Host "Then check the notifier fired -- a webhook 200 means RECEIVED, not succeeded,"
Write-Host "so look at the n8n execution rather than trusting the response code."
