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
OUTPUT="$(make down AUTO=1 2>&1)"
EXIT_CODE=$?

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
