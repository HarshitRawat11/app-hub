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
#
# ---------------------------------------------------------------------------
# THE BATTERY FLAGS ARE LOAD-BEARING. Added 2026-09-13 after the first real
# test of this task did nothing at all.
#
# `New-ScheduledTaskSettingsSet` DEFAULTS to:
#     DisallowStartIfOnBatteries = True
#     StopIfGoingOnBatteries     = True
#
# Those defaults are correct for their intended purpose -- background
# maintenance should not flatten someone's laptop. They are exactly wrong
# here, and the failure is silent:
#
#   - Triggered on battery, the task goes to state **Queued** and simply
#     waits. Not Running, not Failed. No completion event, no output, no
#     error. Observed live: launched 14:13, still Queued at 14:19, because
#     the laptop was unplugged.
#   - Unplugged mid-run, StopIfGoingOnBatteries ABORTS a destroy partway
#     through, which is worse than never starting it.
#
# Why this matters more than it looks: 23:30 is precisely when a laptop is
# likely to be on battery. So the default settings would skip the teardown on
# exactly the nights it was needed, the cluster would bill until morning, and
# nothing anywhere would say so. A cost control that fails silently when
# conditions are inconvenient is not a cost control.
#
# The trade is explicit and small: a teardown is minutes of CPU and a few API
# calls, not a disk-indexing job. Spending that on battery is fine; spending
# $0.30/hour on a forgotten NAT gateway is not.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# -WakeToRun, added 2026-09-18 for D-25.
#
# -StartWhenAvailable (above) already makes Task Scheduler catch up a missed
# run -- but it catches up WHEN THE MACHINE NEXT WAKES, which is the morning.
# Observed: runs at 11:18 and 11:22 IST on nights the laptop slept, against
# 23:30:04 and 23:40:55 IST on the two nights it was awake. The task was never
# broken; the machine was simply asleep.
#
# That distinction is cheap to ignore and expensive to be wrong about: a
# cluster left up on a night the lid is shut bills from 23:30 until whenever
# the laptop next opens. Roughly 12 hours at ~$0.28/hour is about $3.40 -- more
# than a whole working session costs.
#
# THE TRADE, STATED PLAINLY because it affects the owner's machine rather than
# the cloud bill: the laptop will now wake at 23:30 every night, run for a
# couple of minutes and sleep again. On a night with nothing deployed that is
# pure waste -- a few seconds of CPU and a little battery. It is accepted
# because the alternative is only noticed on the nights it costs money.
#
# NOT SUFFICIENT ON ITS OWN. -WakeToRun sets the task's intent; Windows power
# policy decides whether wake timers are honoured at all, and it is commonly
# DISABLED on battery. A task with WakeToRun under a policy that forbids wake
# timers simply does not wake -- silently, which is this project's recurring
# failure shape. The verification below checks both.
#
# To undo: re-run this script with the line removed, or
#   Set-ScheduledTask -TaskName "app-hub nightly teardown" -Settings (
#     New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries
#     -DontStopIfGoingOnBatteries -DontStopOnIdleEnd)
# ---------------------------------------------------------------------------
$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -DontStopOnIdleEnd `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -WakeToRun `
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
# Assert the battery settings actually took. They are the difference between a
# teardown that runs and one that sits in state Queued all night saying nothing.
$st = $check.Settings
Write-Host "  on battery : start=$(-not $st.DisallowStartIfOnBatteries) keep-running=$(-not $st.StopIfGoingOnBatteries)"
if ($st.DisallowStartIfOnBatteries -or $st.StopIfGoingOnBatteries) {
    Write-Host ""
    Write-Host "WARNING: this task will not run on battery power." -ForegroundColor Red
    Write-Host "It will sit in state 'Queued' and produce no output, no error and no"
    Write-Host "completion event -- on exactly the nights a laptop is unplugged."
    exit 1
}

# Assert WakeToRun took, and then assert the thing the task cannot control.
#
# Two separate facts, and only checking the first is how this ends up looking
# configured and behaving exactly as before:
#   1. the TASK asks to wake the machine        -> $st.WakeToRun
#   2. WINDOWS POLICY permits wake timers       -> powercfg
Write-Host "  wake to run: $($st.WakeToRun)"
if (-not $st.WakeToRun) {
    Write-Host ""
    Write-Host "WARNING: -WakeToRun did not take." -ForegroundColor Red
    Write-Host "The teardown will only run when the machine happens to be awake at"
    Write-Host "23:30, and otherwise catch up the next morning -- billing a forgotten"
    Write-Host "cluster overnight. See D-25."
    exit 1
}

# GUIDs rather than names: `powercfg /q SCHEME_CURRENT SUB_SLEEP RTCWAKE` works
# on English Windows and fails on localised installs, where the friendly alias
# differs. The GUID is the same everywhere.
#   SUB_SLEEP = 238c9fa8-...  RTCWAKE (Allow wake timers) = bd3b718a-...
# Values: 0 = Disable, 1 = Enable, 2 = Important Wake Timers Only.
$wake = powercfg /query SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 bd3b718a-0680-4d9d-8ab2-e1d2b4ac806d 2>$null
if ($wake) {
    $ac = ($wake | Select-String 'Current AC Power Setting Index:\s*0x(\w+)').Matches.Groups[1].Value
    $dc = ($wake | Select-String 'Current DC Power Setting Index:\s*0x(\w+)').Matches.Groups[1].Value
    $names = @{ '00000000' = 'Disabled'; '00000001' = 'Enabled'; '00000002' = 'Important only' }
    Write-Host "  wake timers: plugged in = $($names[$ac]) / on battery = $($names[$dc])"
    if ($dc -eq '00000000') {
        Write-Host ""
        Write-Host "WARNING: wake timers are DISABLED on battery." -ForegroundColor Yellow
        Write-Host "-WakeToRun is set on the task, but Windows will ignore it whenever the"
        Write-Host "laptop is unplugged -- which is most nights. The task will not fail; it"
        Write-Host "will simply not wake, and catch up in the morning as before."
        Write-Host ""
        Write-Host "To allow it (your call -- it lets scheduled tasks wake the machine on"
        Write-Host "battery):"
        Write-Host "  powercfg /setdcvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 bd3b718a-0680-4d9d-8ab2-e1d2b4ac806d 1"
        Write-Host "  powercfg /setactive SCHEME_CURRENT"
    }
} else {
    Write-Host "  wake timers: UNKNOWN (powercfg returned nothing)"
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
