# 37 — Proving a scheduled job actually ran  ·  *delegated, short note*

## What it does

Closes `D-25` and `G7` — the question of whether the nightly teardown fires when
the laptop is asleep at 23:30 — and opens `D-31` and `D-32`, both found in the
same evidence. No code changed. This is a note about **how the question was
settled**, because the technique transfers to any unattended job.

## Why it is this way

**A job's own log cannot tell you whether it ran on time.** The teardown writes
`[2026-09-20 23:31 IST] scheduled destroy starting`, which looks like proof and
is not: Windows Task Scheduler also **catches up a missed trigger on wake**, and
a catch-up writes a line that reads identically. On `2026-09-17` the machine woke
at `23:34:56` for its own reasons and the task ran at `23:40:55` — a log at
"about 23:30" proving nothing.

So the closing condition was defined as **two** signals, not one:

| signal | source |
|---|---|
| the teardown ran | its own log file |
| the machine was **woken for it** | `Microsoft-Windows-Power-Troubleshooter` Id 1 |

**And the gap between them is what separates the two cases.** A wake timer fires
*at* the scheduled minute; a catch-up fires whenever the machine happens to wake.

```
09-20  WAKE 23:30:38  ->  run 23:31     =  27 seconds   -- wake timer
09-17  WAKE 23:34:56  ->  run 23:40:55  =   6 minutes   -- catch-up
```

The `09-20` night had `SLEEP 22:02:32` 88 minutes earlier, a Task Scheduler time
trigger (`id=107`) at `23:30:34`, and `exit 0` with `HTTP 200`. **Four sources,
one story.**

## The one thing to know

**`Get-ScheduledTaskInfo` returns nothing for a task that exists**, if you are
not elevated — the same confidently-wrong answer `CLAUDE.md § 9` was written
about. `schtasks /query` is honest about the identical state:

```
schtasks /query /TN "zzz-invented-name"     ->  ERROR: The system cannot find the file specified.
schtasks /query /TN "app-hub nightly teardown"  ->  ERROR: Access is denied.
```

**Different answers mean the task exists and the refusal is permission, not
absence.** Same answer would have meant UNKNOWN. Always run the invented-name
control before believing a negative.

The readable-unelevated source that actually answers "did it run" is
**`Microsoft-Windows-TaskScheduler/Operational`** — `id=107` time trigger,
`id=100` started, `id=200` action started, `id=201`/`102` completed, and
**`id=332` = will not run**. Filter it by task *name*, not by a substring: this
machine has two app-hub tasks plus a **stale duplicate registration** of the
teardown itself (`D-32`), and its `332` events sit in the same log and read as
the real task being blocked. That misreading cost the first twenty minutes of
this investigation.
