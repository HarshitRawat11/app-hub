# 31 — A spend guardrail that runs in AWS  ·  *delegated, short note*

> Written by Claude via the `CLAUDE.md § 2` escape hatch, 2026-09-16, with the
> explanation given first at the owner's request. **Concept skipped:**
> `aws_budgets_budget` is this project's first Terraform resource using
> **nested repeated blocks** — `notification` appears twice in one resource.
> That is how Terraform expresses "a list of sub-objects", and it is the same
> shape as `ingress` rules in a security group, which is where it turns up next.

## What it does

`infra/persistent/budget.tf` adds a **daily** AWS Budget: $3/day, with two
`ACTUAL` alerts at 100% ($3) and 200% ($6), emailing an address supplied
through `var.budget_alert_email` — no default, so `plan` fails rather than
notifying nobody. It lives in the **persistent** stack, so `make down` cannot
destroy it.

It exists because of `D-24`: n8n's `cost-watchdog` stops firing after the
laptop sleeps, and the window it exists to cover — a cluster left up overnight
— is exactly the window in which the laptop is asleep. **This is the only cost
control in the project that runs in AWS rather than on this machine.**

## Why it is this way

**A budget already existed, and checking first changed the design.** The
account has had "My Monthly Cost Budget" ($15/month, four alerts) since
2025-02-01, created in the console. On the day this was written its forecast
alerts were already in `ALARM` — forecast $24.10 against a $15 limit.

So the question was not "add a budget" but "what does the existing one not
do". The answer is in one line of AWS documentation:

> *"Actual alerts are only sent out once per budget, **per budget period**,
> when a budget first reached the actual alert threshold."*

A monthly budget has a monthly period. Once it fires in September it is silent
for the rest of September, whatever gets left running. **A daily budget's
period is one day, so it can speak again tomorrow.** That is the whole reason
this file is `DAILY` rather than a second monthly budget.

$3 is a threshold between two measured numbers, not a round guess: a real
6-hour session is about **$1.70** at the measured $0.28/hour, and a cluster
forgotten for 12 hours or more is **$3.40+**. Legitimate work stays under;
anything that outlived the session goes over.

Two facts checked rather than recalled, both of which had been stated wrongly
in chat first: billing data refreshes **"at least once per day"** (not three
times), and alert-only budgets are **free regardless of count** — the
"first two are free" limit applies to *action-enabled* budgets, which cost
$0.10/day beyond two.

## The one thing to know

**This is a backstop, not a watchdog, and the difference is not a detail.**

AWS Budgets watches *billing data*, which is a different system from anything
that observes running resources. Since that data updates roughly daily:

- it **cannot** tell you the cluster came up twenty minutes ago
- it **can** tell you that yesterday cost more than a working session should

`make status` remains the only honest answer to *"is anything running right
now"*. What this buys is the case nothing else covers — the night you forgot,
with the laptop shut.

There is a second trap worth naming, because it is the same disease as
everything else in this project: the file deliberately has **no cost filter**.
Filtering by tag sounds more precise, but a tag only reaches cost data after
being activated as a *cost allocation tag* in the Billing console — a manual
step outside Terraform. A filter on an unactivated tag matches nothing, so the
budget would sit at $0.00 forever and never alert. **A guardrail that is silent
because it is broken looks exactly like one that is silent because all is
well** — see `learn/20`, where the same sentence applies to a dead monitor.
