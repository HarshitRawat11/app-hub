# 26 — A repository layer, and a test suite that was too slow to be used · *delegated, short note*

> **Short note** (`CLAUDE.md § 2`). Claude wrote this. `learn/13` covers the
> reasoning behind DynamoDB and the ephemeral/persistent split; this records
> what the code turned into.

## What it does

`links-service` no longer knows where its data lives. `app/repository.py` defines a `LinkRepository` **Protocol** with two implementations — `InMemoryLinkRepository` (a dict) and `DynamoDBLinkRepository` (the `app-hub-links` table from the persistent Terraform stack). Which one you get is decided once at startup by whether `LINKS_TABLE_NAME` is set.

Ids changed from an incrementing integer to a **server-generated UUID string**. 38 tests, up from 15.

**Status: verified against the real `app-hub-links` table on 2026-09-13.** 11 checks, 0 failures, and the table was left byte-identical to how it was found.

> **The earlier status line here said this needed `C-05` first. That was wrong, and the error is worth more than the correction.** IRSA is what a **pod** needs to reach DynamoDB. It is not what a laptop needs — boto3's default credential chain in WSL already resolves to `terraform-learning`, which owns the table. Conflating *"the deployed service cannot reach DynamoDB yet"* with *"this code cannot be verified yet"* kept the task marked blocked for three days on a blocker that only applied to one of the two.

## Why it is this way

**The id change is the load-bearing one, not the interface.** `global next_id` could not survive more than one replica: each pod starts at 1 and hands out colliding ids, so a write on one pod silently overwrites a *different* record on the other. That is what `D-02` was about and why `replicas` was pinned to 1. UUIDs need no coordination between pods at all.

This is also where `C-04` pays off. The table declares its `id` key attribute as type **`S`**, decided before any of this code existed — and a key attribute's type cannot be changed without destroying and recreating the table. Getting that right in advance cost nothing; getting it wrong would have meant migrating the one table in the project that is never supposed to be destroyed.

**A `Protocol`, not an abstract base class.** Nothing inherits from it. A class that *has* these methods **is** a `LinkRepository`, so `DynamoDBLinkRepository` never imports the in-memory one and neither imports a shared base. Type checkers verify the shape; there is no runtime coupling.

**The backend switch is the presence of `LINKS_TABLE_NAME`, not a `LINKS_BACKEND=dynamodb` flag.** One variable cannot disagree with itself. A backend flag set to `dynamodb` with no table name is a configuration you can express and should not be able to. Unset means in-memory, so local development needs zero configuration — the same shape as gateway's `LINKS_SERVICE_URL`.

**Two DynamoDB details that are quietly wrong by default:**

- `delete_item` **succeeds whether or not the item existed.** Without `ReturnValues="ALL_OLD"` there is no way to tell the two apart, and `DELETE /links/<nonexistent>` would answer `200` instead of `404` — a delete that cannot tell you whether it deleted anything.
- `put_item` with `exclude_none` omits an absent optional field rather than storing `NULL`. Storing NULL makes every reader handle a value that means "not set"; `Link`'s default fills it back in on read instead.

**The contract tests run every assertion twice** — once against the dict, once against a real DynamoDB table faked in-process by `moto`. That is what makes the interface real rather than aspirational: an interface only the dict satisfies is a dict with extra steps, and you would find out in the cluster, where the cost is a broken deploy rather than a red test.

## The one thing to know

**The suite first took 573 seconds, and that is a defect, not an inconvenience.** `make test` exists to be a fast feedback loop; a ten-minute suite is one nobody runs, which makes it worth nothing.

Profiling rather than guessing:

```
import boto3:        13.6s
import moto:          5.6s
first resource():    37.5s
second resource():    0.0s
```

Botocore loads its service models from thousands of small JSON files, and this project lives on `/mnt/c`, which WSL reaches over a slow 9p mount. **That cost is cached per process — but `mock_aws()` per test defeated the cache and re-paid it every time.** Moving the mock and the client into a **session-scoped** fixture, with per-test isolation restored by emptying the table through the repository's own interface, took it to **somewhere between ~20 s and ~115 s** — see below, because the spread is the finding.

> **Corrected twice, on 2026-09-13, and the second correction is the useful one.**
>
> This file first said **39 s**. Re-timing gave 102 s and 114 s, so that was replaced with “~100–115 s”. An hour later the same suite ran in **22.8 s**. Three “measurements”, three different answers, and **two of them were written down as facts.**
>
> **The number is not a number, it is a range, and the variable is the OS page cache.** botocore reads thousands of small JSON service models; on `/mnt/c` that is a slow 9p mount when cold and fast when Windows still has the files cached. So the suite is ~20 s warm and ~115 s cold, and a single figure was never going to be honest.
>
> **The improvement is what was real all along** — 573 s to tens of seconds, by fixing fixture scope. That held across every run. The lesson is to record what you actually controlled, not the stopwatch reading that happened to accompany it.

Two things worth carrying:

- **The numbers named the cause in one command.** "Tests are slow" could have been moto, the dict, pytest collection, or the filesystem. Four timings said it was the first client construction, and the 0.0s second call said it was cacheable — which is what pointed at fixture scope rather than at moto itself.
- **Fixture scope is a performance decision, not just a style one.** Function-scoped is the safe default and is usually right. When setup is expensive *and* cacheable, the question becomes what isolation actually requires — here, an empty table, not a fresh world.

Second thing, smaller: **`TestClient(app)` outside a `with` block never runs `lifespan`.** Since the repository is now created there, `app.state.repo` would not exist and every HTTP test would fail with `AttributeError` rather than an assertion. The autouse fixture in `test_links.py` supplies it, which does isolation and setup in one move.

## What the real table showed that `moto` could not

Most of it matched: UUID strings work as an `S` key, `exclude_none` genuinely **omits** the `icon` attribute rather than storing NULL (confirmed by reading the raw item through the AWS CLI, not through our own code), and `ReturnValues="ALL_OLD"` really does distinguish deleting something from deleting nothing — a second `DELETE` answers `404`.

**One difference is real and did not bite only by luck.** `moto` answers every read immediately. A real DynamoDB `get_item` and `scan` are **eventually consistent by default** — a read after a write may legitimately return nothing. Here it returned in 0.036 s every time, which is the normal case and **not a guarantee**. Nothing in `links-service` depends on read-after-write today; a feature that does would need `ConsistentRead=True` and would pass every test in this repository before failing in production.

**The multi-replica claim was proven rather than argued.** Two links-service processes, same table, one record created by each: distinct ids, and **each process read the other's record back**. With `global next_id` both would have issued `1`; with the in-memory dict each would have answered `404` for the other's. That is the whole reason this step exists.

## Verify it yourself

```bash
make test
```

38 + 47 tests. Wall time is dominated by links-service and swings from ~25 s to ~2 min depending on whether botocore's service models are still in the page cache (see the correction above). Gateway's 47 run in about 4 s either way. To see the contract structure, note that each storage test reports twice:

```bash
cd links-service && uv run pytest tests/test_repository.py -v | head -20
```

Every name ends in `[in-memory]` or `[dynamodb]`. To watch the slow version come back, change `scope="session"` to the default on `dynamo_repo` and time it — it returns to roughly ten minutes.
