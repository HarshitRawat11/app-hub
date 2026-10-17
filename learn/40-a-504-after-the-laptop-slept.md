# 40 — A 504 after the laptop slept  ·  *delegated, short note*

## What it does

links-service's DynamoDB client now has explicit timeouts: **1 second** to connect,
**1 second** to read, and **2 attempts in total**. Before this change it had none,
so it ran on botocore's defaults: **60 seconds** each, read from
`botocore/endpoint.py` (`DEFAULT_TIMEOUT = 60`) rather than recalled.

The trigger was `D-34`. On 2026-10-17 the first dashboard load after a 17-hour sleep
returned *"links-service did not answer within 3 seconds. HTTP 504"*. A refresh fixed
it. While diagnosing it, a second fault turned up (`D-35`): `localhost:8001` was dead
while the tailnet route still worked. That one is Docker Desktop's port forwarder,
and it has a workaround but no fix.

## Why it is this way

**Two layers with mismatched patience.** gateway gives links-service 3 seconds.
links-service gave DynamoDB 60. Whenever the inner layer is slower than the outer
layer's budget, the outer one decides what the user sees, and a 60-second wait
becomes a 504 at second 3. boto3 also pools its HTTPS connections and never ages
them out. A laptop that sleeps is exactly the host where pooled connections die
silently.

**The numbers are a budget, worked out in the comment beside them:** a 1s timeout
on a dead connection, almost no retry backoff (DynamoDB's base is 0.025s), then a
fresh attempt. That's typically 1.1–2.3s against gateway's 3s. **The comment also
says where it is not airtight**: under botocore's older backoff path, a cold
reconnect can reach ~3.25s. A normal Scan takes ~45ms, so 1s is still twenty times
headroom.

**The fix is also the experiment.** Two causes fit the evidence: a stale DynamoDB
connection, or Docker networking settling after the wake. The fix only addresses
the first. So if morning 504s stop, that was the cause, and if they don't, it's
ruled out. Either result moves `D-34` forward.

## The one thing to know

**Three checks failed the same way during this work. Each returned a clean-looking
answer about something it could not see.**

1. **`docker compose logs --since <timestamp>` returned zero lines** for a window
   that contained lines. It did this twice. `--tail` worked.
2. **"links-service never logged the failed request" looked like proof it never
   arrived.** But uvicorn writes no access line when the client has already hung
   up, and gateway hangs up at 3s. Proven by sending a request with a 5ms client
   timeout: no line appeared.
3. **The first draft asked for `max_attempts: 2` and got three attempts.**
   botocore's `max_attempts` counts *retries* and silently resolves it to
   `total_max_attempts=3`. The budget test **passed** anyway, because it read the
   constant (what was asked for) and not `client.meta.config` (what the client
   actually resolved). Both guard tests now read the resolved config, and both were
   run against the original bug to show they fail on it.

The common cure, and the reason this project keeps writing it down: **before
trusting a check's silence, show it can see something you know is there.**
