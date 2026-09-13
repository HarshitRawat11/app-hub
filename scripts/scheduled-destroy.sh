#!/usr/bin/env bash
#
# Unattended teardown + report to n8n (task N-00b).
#
# Runs the SAME teardown as `make down` -- deliberately, so there is one
# teardown path, not two that can drift. AUTO=1 skips terraform's confirmation
# prompt, which is required for a scheduled run with no terminal attached.
#
# Then POSTs the result to the n8n `destroy-status` webhook, which emails it.
#
# WHY THE DESTROY RUNS HERE AND NOT INSIDE n8n:
#   Running `terraform destroy` from n8n's Execute Command node would need
#   Terraform in the container, the infra/ directory mounted, and -- the real
#   objection -- AWS credentials with destroy rights stored persistently in a
#   long-running web app. Keeping it local means those credentials stay in
#   ~/.aws and never enter n8n. n8n only ever receives a status string.
#
# Run from WSL. Schedule via Windows Task Scheduler invoking wsl.exe (a cron
# inside WSL is unreliable -- WSL may simply not be running at the trigger time).

set -uo pipefail   # NOT -e: a failed destroy must still be reported, not abort the script

cd "$(dirname "$0")/.."
PROJECT_DIR="$(pwd)"

# ---------------------------------------------------------------- logging ---
#
# ADDED 2026-09-13, AFTER AN UNATTENDED RUN VANISHED WITHOUT TRACE.
#
# The Windows Task Scheduler action is `wsl.exe -e bash -lc "<this script>"`
# with no redirection, so everything this script echoes went NOWHERE. A run
# that fails before the webhook POST therefore left no evidence at all --
# not a log, not an n8n execution, nothing. The Task Scheduler said the task
# had launched and simply never said anything else.
#
# That is the same shape as every other bug this project has spent time on:
# a step that looked like it worked because nothing was watching. An
# unattended job whose only output channel is the thing that might fail is
# not observable, and an unobservable teardown is one you cannot trust to
# protect you from a NAT gateway bill.
#
# `tee` rather than a plain redirect so an interactive run still prints to
# the terminal. The log is per-run, timestamped, and gitignored.
LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/scheduled-destroy-$(date +%Y-%m-%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== scheduled-destroy ==="
echo "log        : $LOG_FILE"
echo "project    : $PROJECT_DIR"
echo "user       : $(id -un 2>/dev/null || echo unknown)"
echo "home       : ${HOME:-unset}"
# The single most useful line here. The task's PRINCIPAL decides which
# Windows account launches wsl.exe, which decides the WSL home directory,
# which decides whether ~/.aws/ holds the app-hub credentials at all. If this
# says "no credentials", the teardown was never going to work and the cause
# is the scheduled task's principal, not Terraform.
echo -n "aws ident  : "
aws sts get-caller-identity --query 'Arn' --output text 2>&1 | head -1
echo "========================="

# The webhook URL lives in n8n/.env alongside the API key. Never hardcoded, and
# never printed.
if [[ -f n8n/.env ]]; then
  set -a
  # shellcheck disable=SC1091
  . ./n8n/.env
  set +a
fi

# Prod webhook path. n8n also exposes /webhook-test/... but that only fires while
# you have the editor open with "Listen for test event" active.
WEBHOOK="${N8N_WEBHOOK_URL:-${N8N_BASE_URL:-http://localhost:5678}/webhook/destroy-status}"

STARTED_AT="$(TZ=UTC date -d "@$(( $(date +%s) + 19800 ))" '+%Y-%m-%d %H:%M IST')"

echo "[$STARTED_AT] scheduled destroy starting in $PROJECT_DIR"

# Capture everything: the report is only useful if it carries the failure text.
# Tee rather than capture, so the teardown's own output reaches the log as it
# happens AND is still available to build the n8n payload from.
#
# The first version of this was `OUTPUT="$(make down AUTO=1 2>&1)"`, which put
# every line into a variable and nowhere else. On a successful no-op that looks
# fine; on a real failure the log would say "failure (exit 2)" and nothing
# more, with the actual error surviving only inside the email -- and lost
# completely if the webhook POST were the thing that failed. A log that goes
# blank exactly when something breaks is not a log.
#
# WHY PIPESTATUS[0] AND NOT `$?`. In plain bash a pipeline's `$?` is the LAST
# command's status -- tee's -- which is essentially always 0, so a failed
# teardown would report success and email you to say so. This script sets
# `pipefail` at the top, which happens to fix that, so `$?` would work here
# today. PIPESTATUS[0] is used anyway because it names the thing we actually
# mean, and does not quietly depend on an option someone could remove.
#
# Measured rather than assumed, because the first version of this comment
# claimed `$?` would be 0 and a two-line test disproved it:
#     without pipefail:  $? = 0   PIPESTATUS[0] = 2
#     with pipefail:     $? = 2   PIPESTATUS[0] = 2
#
# One real gotcha while testing: PIPESTATUS is CLOBBERED by the very next
# command, including an `echo` that tries to print it alongside `$?`. It has
# to be read on the immediately following line, which is why the assignment
# below sits directly under the pipeline with nothing in between.
TEARDOWN_OUT="$(mktemp)"
make down AUTO=1 2>&1 | tee "$TEARDOWN_OUT"
EXIT_CODE="${PIPESTATUS[0]}"
OUTPUT="$(cat "$TEARDOWN_OUT")"
rm -f "$TEARDOWN_OUT"

if [[ $EXIT_CODE -eq 0 ]]; then
  STATUS="success"
else
  STATUS="failure"
fi

FINISHED_AT="$(TZ=UTC date -d "@$(( $(date +%s) + 19800 ))" '+%Y-%m-%d %H:%M IST')"
echo "[$FINISHED_AT] destroy finished: $STATUS (exit $EXIT_CODE)"

# Terraform output is long and full of characters that break naive JSON building.
# jq --arg handles the escaping; keep the tail so the email stays readable but
# still contains the actual error.
if command -v jq >/dev/null; then
  PAYLOAD="$(jq -n \
    --arg status "$STATUS" \
    --arg exit_code "$EXIT_CODE" \
    --arg started "$STARTED_AT" \
    --arg finished "$FINISHED_AT" \
    --arg output "$(printf '%s' "$OUTPUT" | tail -c 4000)" \
    '{status: $status, exit_code: $exit_code, started: $started, finished: $finished, output: $output}')"
else
  echo "warning: jq not found; sending a minimal payload" >&2
  PAYLOAD="{\"status\":\"$STATUS\",\"exit_code\":\"$EXIT_CODE\"}"
fi

# --max-time so a hung n8n cannot wedge a scheduled task forever.
# Never use -v here: it prints request headers.
HTTP_CODE="$(printf '%s' "$PAYLOAD" \
  | curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
      -X POST "$WEBHOOK" \
      -H 'Content-Type: application/json' \
      --data-binary @- 2>/dev/null)"

if [[ "$HTTP_CODE" == "200" ]]; then
  echo "reported to n8n (HTTP $HTTP_CODE)"
else
  # A failed notification must not mask a failed destroy, so this only warns.
  echo "warning: could not reach the n8n webhook (HTTP ${HTTP_CODE:-000}). Is n8n running and the workflow ACTIVE?" >&2
  echo "         an inactive workflow returns 404 on /webhook/... -- activate it in the n8n UI." >&2
fi

exit $EXIT_CODE
