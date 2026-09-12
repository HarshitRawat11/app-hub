# 26 — A repository layer, and a test suite that was too slow to be used · *delegated, short note*

> **Short note** (`CLAUDE.md § 2`). Claude wrote this. `learn/13` covers the
> reasoning behind DynamoDB and the ephemeral/persistent split; this records
> what the code turned into.

## What it does

`links-service` no longer knows where its data lives. `app/repository.py` defines a `LinkRepository` **Protocol** with two implementations — `InMemoryLinkRepository` (a dict) and `DynamoDBLinkRepository` (the `app-hub-links` table from the persistent Terraform stack). Which one you get is decided once at startup by whether `LINKS_TABLE_NAME` is set.

Ids changed from an incrementing integer to a **server-generated UUID string**. 38 tests, up from 15.

**Status: written and unit-tested, NOT verified against the real table.** That needs `C-05` to give a pod credentials.

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

Botocore loads its service models from thousands of small JSON files, and this project lives on `/mnt/c`, which WSL reaches over a slow 9p mount. **That cost is cached per process — but `mock_aws()` per test defeated the cache and re-paid it every time.** Moving the mock and the client into a **session-scoped** fixture, with per-test isolation restored by emptying the table through the repository's own interface, took it to **roughly 100–115 seconds**.

> **Corrected 2026-09-13.** This file first recorded **39 seconds**. Re-timed twice while doing `S-03`, the suite takes 102 s and 114 s — so 39 s was a single warm run that does not reproduce, written down as if it were the number. The *improvement* is real and is the point (573 s → ~110 s, about 5×), but the specific figure was optimistic and nothing re-measured it. Same shape as every other stale claim this project has caught: **a number with no consumer is untested.**

Two things worth carrying:

- **The numbers named the cause in one command.** "Tests are slow" could have been moto, the dict, pytest collection, or the filesystem. Four timings said it was the first client construction, and the 0.0s second call said it was cacheable — which is what pointed at fixture scope rather than at moto itself.
- **Fixture scope is a performance decision, not just a style one.** Function-scoped is the safe default and is usually right. When setup is expensive *and* cacheable, the question becomes what isolation actually requires — here, an empty table, not a fresh world.

Second thing, smaller: **`TestClient(app)` outside a `with` block never runs `lifespan`.** Since the repository is now created there, `app.state.repo` would not exist and every HTTP test would fail with `AttributeError` rather than an assertion. The autouse fixture in `test_links.py` supplies it, which does isolation and setup in one move.

## Verify it yourself

```bash
make test
```

38 + 47 tests, around two minutes — almost all of it links-service (see the correction above). To see the contract structure, note that each storage test reports twice:

```bash
cd links-service && uv run pytest tests/test_repository.py -v | head -20
```

Every name ends in `[in-memory]` or `[dynamodb]`. To watch the slow version come back, change `scope="session"` to the default on `dynamo_repo` and time it — it returns to roughly ten minutes.
