# 23 — Testing the links API, and two cosmetic fixes · *delegated, short note*

> **Short note** (`CLAUDE.md § 2`). Claude wrote this one. `learn/14` covers the
> concepts in full — `TestClient`, fixtures, the shared-state trap — and is worth
> reading first if any of the below is unfamiliar. This file records what was
> actually built and the decisions that went into it.

## What it does

`links-service/tests/test_links.py` — **14 tests**, run with `uv run pytest` from `links-service/`. Closes `C-02`, which was blocking `C-06`.

Also closed `D-09` (leftover `description = "Add your description here"` in `pyproject.toml`) and `D-10` (handlers renamed from `camelCase` to `snake_case` in both `links-service` and `gateway`).

Coverage, so you can review the list rather than the code:

| | |
|---|---|
| `/health` | returns `{"status": "ok"}` |
| `GET /links` | empty before anything is created; returns every record after |
| `POST /links` | returns the stored record with an `id` |
| **`GET /links` after create** | **the record has its `id`** — `D-01` regression |
| **`GET /links/{id}` after create** | **the record has its `id`** — `D-01` regression |
| ids | increment from 1 |
| `icon` | optional, defaults to `null` |
| `GET /links/999` | `404` with `{"detail": "Link not found"}` |
| `DELETE /links/{id}` | returns `{"deleted": id}`, **and the record is actually gone** |
| `DELETE /links/999` | `404` |
| `POST` missing a required field | `422` |
| `POST` with a client-supplied `id` | ignored; server still assigns `1` |
| `GET`/`DELETE /links/abc` | `422` |

Not covered, deliberately: concurrency (the service is `replicas: 1` until `C-06`), and persistence across restarts (there isn't any until `C-04`–`C-06`).

## Why it is this way

**`TestClient` drives the app in-process over ASGI** — no uvicorn, no port, no network. That matters practically: the suite cannot collide with a real `links-service` on 8000, and it runs in seconds. You are testing the app, not a deployment of it.

**The whole suite is built around one trap.** `links_db` and `next_id` are module-level globals, so in a single pytest process the second test to run sees the first test's records and ids. An `autouse` fixture resets both before every test.

That failure mode is worth recognising because it is **order-dependent**: run one test alone and it passes; run the file and it fails; reorder the file and *different* tests fail. If you ever see that pattern, look for shared state before looking at the tests themselves.

**Two tests are explicit `D-01` regressions**, and the reason is instructive. The original bug stored the incoming `LinkCreate` instead of the constructed `Link`, so `POST` returned exactly the right shape while every *read* came back with no `id`. **A test asserting only on the POST response would have passed throughout.** So both read paths — `GET /links` and `GET /links/{id}` — assert the `id` independently.

**`D-10` was safe to do because the tests existed first.** Renaming four handlers is behaviour-neutral in principle; all 14 tests passing afterwards is what turns that into a fact. This is the small version of why `C-06` (the storage refactor) was blocked on `C-02` — you don't restructure code you can't verify.

## The one thing to know

**Three of these would have failed with a `ModuleNotFoundError`, not an assertion error, without a line in `pyproject.toml`.**

pytest builds `sys.path` from where it finds test files. With `tests/test_links.py` and no `__init__.py`, it inserts `tests/` — **not** the project root. So `from app.main import app` fails with:

```
ModuleNotFoundError: No module named 'app'
```

which reads like a broken install or a missing dependency, and sends you to `uv sync` rather than to your path configuration. The fix is one setting:

```toml
[tool.pytest.ini_options]
pythonpath = ["."]
testpaths = ["tests"]
```

Second thing, smaller but real: **starlette's `TestClient` now deprecates `httpx` in favour of `httpx2`.** The suite ran fine but printed a warning on every invocation. `httpx2` 2.12.0 resolves cleanly, and `httpx` was only ever in `links-service` as a test dependency, so the swap was clean — warning gone, all 14 still passing.

Note this leaves an **inconsistency**: `gateway` uses `httpx` 0.28 as a *runtime* dependency for its `AsyncClient`, and that has not moved. Nothing is broken — no deprecation applies there — but two services in one project using different HTTP clients is the kind of thing that surprises someone later. Tracked as `D-17`.

## Verify it yourself

```bash
cd links-service && uv run pytest -v
```

14 passed. To see the shared-state trap the fixture prevents, comment out the two lines inside `reset_state` and run again — several tests fail on ids that are no longer `1`, and *which* ones fail depends on the order they ran in.
