# 20 — Testing an n8n workflow, and finding a monitor that had died silently

## What we did

Finished `terraform-destroy-notifier` — `Webhook → If → Success/Failure` — and tested both branches with fake payloads instead of waiting for a real teardown.

Both branches routed correctly. Both then failed at the Gmail node, because the OAuth refresh token had expired. And the same credential is used by **`cost-watchdog`**, which means the project's cost safety net had been dead for days without anyone noticing.

## Why

Two reasons to test with fake payloads rather than a real destroy.

**The failure branch only ever runs when something has already gone wrong.** If you first exercise it during a genuinely failed teardown, you are debugging two things at once — the teardown *and* the notifier. Test it while everything is calm.

**A real destroy takes ~15 minutes and costs money to set up.** A `curl` takes a second. Anything you can test without infrastructure, you should.

## Key concepts

### 1. HTTP 200 from a webhook means "received", not "worked"

```
POST /webhook/destroy-status  ->  200  {"message":"Workflow was started"}
```

That is n8n confirming it *accepted* the request and kicked off an execution. It says nothing about whether the execution succeeded. n8n replies immediately and runs the workflow asynchronously.

Both of our test payloads returned 200. Both executions **errored**.

This is the same trap as the canvas green check from earlier project history — *"did not halt"* is not *"succeeded"* — one layer out. **The webhook's response tells you about the webhook, not about the workflow.**

The real answer is in the executions list:

```bash
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" \
  "$N8N_BASE_URL/api/v1/executions?workflowId=<id>&limit=5" \
  | jq -r '.data[] | "id=\(.id) status=\(.status)"'
```

```
id=23  status=error
id=22  status=error
```

### 2. `runData` tells you which branch actually executed

To prove an `If` node routes correctly you need to know *which* nodes ran, not just that something failed. Fetch the execution with data:

```bash
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" \
  "$N8N_BASE_URL/api/v1/executions/23?includeData=true" \
  | jq -r '.data.resultData.runData | keys[]'
```

```
Failure
If
Webhook
```

For the success payload it listed `Success`, `If`, `Webhook`. **That is the proof the routing works** — the success payload reached the `Success` node and the failure payload reached the `Failure` node.

Separating "did it route correctly" from "did the final node succeed" is what let us say the workflow was *correct* while still being *non-functional*. Those are different findings with different owners: one is a workflow bug, the other is a credential problem.

### 3. The `body` nesting in n8n webhooks

An n8n Webhook node does not hand the POSTed JSON straight through. It wraps it, putting the request body under `body`, alongside `headers` and `query`. So:

```
{{ $json.status }}        ✗ undefined
{{ $json.body.status }}   ✓
```

Get this wrong and the `If` node silently takes the false branch for *everything*, because `undefined != "success"`. No error — just consistently wrong routing. Worth checking first whenever an `If` after a Webhook behaves oddly.

### 4. OAuth: three tokens, three lifetimes

The error was:

```
The credential "Gmail account" needs to be reconnected.
Access could not be refreshed because the connected account has revoked access,
the refresh token expired, or the account password or permissions changed.
```

Three separate things are involved, and only one of them died:

| Thing | Stored where | Lifetime |
|---|---|---|
| **Client ID + Secret** | Google Cloud project | indefinite |
| **Refresh token** | n8n's encrypted DB | **~7 days in Testing mode** |
| **Access token** | memory | ~1 hour, auto-renewed via the refresh token |

n8n silently exchanges the refresh token for access tokens. When the refresh token dies, that chain breaks — but the client credentials underneath are untouched.

**So the fix is re-consent, not re-registration.** Creating a new OAuth client would also work, but leaves an orphan in Google Cloud and means re-entering the ID and secret for no benefit.

**The root cause is a Google policy:** OAuth apps whose consent screen is in *Testing* status issue refresh tokens that expire after 7 days. Publishing the app (Google Cloud → APIs & Services → OAuth consent screen → **Publish App**) removes that. It warns about being unverified, which is irrelevant when you are the only user.

### 5. The real finding: "active" does not mean "working"

`cost-watchdog` shows `active: true`. It is scheduled, enabled, and n8n reports it as healthy. It uses the **same Gmail credential**.

So it would have run at 5 PM, called the EKS API, and **failed at the Gmail node** — meaning a cluster left running overnight would have produced **no warning at all**.

Nothing surfaced this, because:

- The workflow only fires when there *is* a cluster, and there has not been one
- A workflow that never fires never errors
- n8n's own UI reports it as active and fine

**The general lesson: a monitor is a piece of software, and it fails like any other — but its failures are invisible by construction, because its normal state is silence.** You cannot tell a working watchdog from a dead one by looking at it. The only way to know is to *exercise it deliberately*.

This is why the discovery came from testing an unrelated workflow. We never tested the watchdog; we tested the notifier and found the shared dependency.

**Practical consequence:** a monitor needs its own liveness check, or a periodic deliberate exercise. "It hasn't alerted" and "there is nothing to alert about" look identical from outside.

### 6. Scheduled workflows cannot be triggered through the public API

Unlike a Webhook workflow, `cost-watchdog` starts from a `Schedule Trigger`. Confirmed rather than assumed:

```
POST /api/v1/workflows/WdHcWWqsLkVskKaM/run  ->  405  {"message":"POST method not allowed"}
```

The n8n public API has no manual-execution endpoint. The options are: wait for the schedule, or click **"Test workflow"** in the UI.

### 7. Why testing `cost-watchdog` needs a cluster

Even with a working credential it would send nothing right now. It calls:

```
https://eks.ap-south-1.amazonaws.com/clusters/app-hub-eks
```

With no cluster that returns **404**, and every node is set to `onError: stopWorkflow`, so the workflow halts there and never reaches Gmail.

That is the design working, not a bug — *404 (cluster gone) halts silently; 200 (still up) proceeds to email*. A watchdog that emailed when nothing was running is a watchdog you would learn to ignore.

The honest consequence: **`cost-watchdog` cannot be end-to-end tested without spending money.** Fold it into the next real session rather than starting a cluster just for it.

## Walkthrough

Firing a fake payload at the production webhook:

```bash
curl -sS -X POST "$N8N_BASE_URL/webhook/destroy-status" \
  -H "Content-Type: application/json" \
  -d '{"status":"failure","exit_code":"1","output":"Error: DependencyViolation: The subnet has dependencies and cannot be deleted."}'
```

Note `/webhook/` (production, needs the workflow **active**) versus `/webhook-test/` (only live while the editor is open with "Listen for test event" clicked). A 404 on the production path almost always means the workflow is not active — n8n's error body says exactly that:

```
"The requested webhook \"POST destroy-status\" is not registered."
"hint":"The workflow must be active for a production URL to run successfully."
```

Then check what actually happened, in two steps: status first, then `runData` for the branch.

## Gotchas

- **A webhook 200 is not a success.** Always check the execution status separately.
- **`$json.body.status`, not `$json.status`.** The Webhook node wraps the payload.
- **A wrong expression in an `If` does not error** — it just routes everything to false. Silent and consistent, which reads like a logic bug.
- **OAuth in Testing mode expires refresh tokens every ~7 days.** Publish the consent screen.
- **`active: true` says the workflow will *run*, not that it will *succeed*.**
- **A monitor that has never fired has never been tested.** Silence is indistinguishable from death.
- **`onError: stopWorkflow` means expected failures look identical to real ones** in the executions list — both are just "did not complete". That is the right trade here, but it means the executions list alone will not tell you whether the watchdog is healthy.

## Verify it yourself

Check whether a workflow is active, and how many nodes it has:

```bash
wsl -e bash -lc 'cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub/n8n && set -a && . ./.env && set +a && curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_BASE_URL/api/v1/workflows?limit=250" | jq -r ".data[] | \"active=\(.active) nodes=\(.nodes|length) \(.name)\""'
```

Fire a test payload and then check what really happened:

```bash
wsl -e bash -lc 'cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub/n8n && set -a && . ./.env && set +a && curl -sS -o /dev/null -w "webhook %{http_code}\n" -X POST "$N8N_BASE_URL/webhook/destroy-status" -H "Content-Type: application/json" -d "{\"status\":\"success\"}" && sleep 5 && curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_BASE_URL/api/v1/executions?workflowId=wI0KmRrmlsVxdGsp&limit=1" | jq -r ".data[] | \"execution \(.id) status=\(.status)\""'
```

If it says `error`, get the reason:

```bash
wsl -e bash -lc 'cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub/n8n && set -a && . ./.env && set +a && curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_BASE_URL/api/v1/executions/<ID>?includeData=true" | jq -r ".data.resultData.error | \"node: \(.node.name)  msg: \(.message)\""'
```

## Going deeper

- [n8n Webhook node](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/) — the production vs test URL distinction, and the payload shape
- [n8n executions API](https://docs.n8n.io/api/api-reference/#tag/Execution)
- [Google OAuth: refresh token expiration](https://developers.google.com/identity/protocols/oauth2#expiration) — the 7-day Testing-mode rule
- [Publishing an OAuth consent screen](https://support.google.com/cloud/answer/10311615)

---

**Open:** `D-13`. Until the Gmail credential is reconnected, **verify teardown with `make status`, not by waiting for an email.** The watchdog cannot warn you.
