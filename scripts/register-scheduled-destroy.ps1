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

Write-Host "Registered '$TaskName'."
Write-Host ""
Write-Host "Verify:"
Write-Host "  Get-ScheduledTask -TaskName '$TaskName' | Format-List TaskName,State"
Write-Host ""
Write-Host "Test it now WITHOUT waiting for the trigger (safe on an empty account):"
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'"
Write-Host ""
Write-Host "Then check the notifier fired -- a webhook 200 means RECEIVED, not succeeded,"
Write-Host "so look at the n8n execution rather than trusting the response code."
