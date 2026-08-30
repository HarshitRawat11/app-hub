# 14 — Testing a FastAPI service with pytest

> **This is a guide, not a record.** `C-02` is yours to implement by hand — there are no tests anywhere in this project yet, so it is a new concept, and `CLAUDE.md § 2` says the first implementation is written by the owner. This file explains the mechanisms *before* you write, so you are not reverse-engineering a finished artifact.

## What you are building

A test suite for the links CRUD endpoints: create → list → get → delete, plus the two 404 paths. Roughly six tests in `links-service/tests/test_links.py`.

## Why

Three reasons, in increasing order of importance here.

**1. The bug that already happened.** `C-01` was `links_db[next_id] = link` instead of `= new_link`. `POST` returned the right thing, so it looked fine. Only reading back through a *different* endpoint exposed it. A single `create → get` test would have caught it the moment it was written, instead of it sitting in `master` for weeks.

**2. You are about to change storage.** `C-04`–`C-06` swap the in-process dict for DynamoDB. That is a rewrite of every handler's data access. **Tests are what make that refactor safe** — they let you change the implementation and know the behaviour did not move. Writing them *before* the refactor is the whole point; writing them after proves only that you preserved whatever you ended up with.

**3. CI needs something to run.** `R-05` is Jenkins-in-EKS running test → build → push. Without tests, that pipeline's first stage is a no-op.

## Key concepts

### 1. `TestClient` — HTTP without a server

```python
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)
response = client.post("/links", json={...})
```

`TestClient` wraps your app and lets you make requests against it **in-process** — no uvicorn, no port, no network. It builds an ASGI request, hands it to the app, and gives you back a response object with `.status_code` and `.json()`.

This matters because it means tests are fast (milliseconds), need no setup or teardown of a server, and cannot collide on a port when run in parallel.

It comes from Starlette and is built on `httpx`, which is why `httpx` is a dependency of the test suite even though you never import it directly.

**The mental model: you are testing the app through its real HTTP interface — routing, validation, serialisation, status codes — without the transport.** That is a genuinely good level to test at. It is not a unit test of a function; it is a test of the endpoint contract.

### 2. The shared-state trap — the thing that will actually bite you

This is the one to understand before writing a line:

```python
links_db: dict[int, Link] = {}   # module-level
next_id = 1                      # module-level
```

These are **module-level globals**. They are created once when `app.main` is first imported, and they persist for the entire test session.

So:

- Test A creates a link → `links_db` now has 1 item, `next_id` is 2
- Test B runs `GET /links` expecting an empty list → **gets test A's link, and fails**
- Reorder the tests → different failures

Worse, it makes tests *order-dependent*, which is the most demoralising kind of flaky test: each passes alone, the suite fails together.

**The fix is a fixture that resets the state before every test.** Something along these lines — you write the real one:

```python
import pytest
from app import main

@pytest.fixture(autouse=True)
def reset_state():
    main.links_db.clear()
    main.next_id = 1
    yield
```

Two things to note. `autouse=True` means it runs for every test without being requested — appropriate here because *every* test needs it. And `main.links_db.clear()` mutates the existing dict rather than rebinding it; `main.links_db = {}` would also work, but `clear()` is safer if anything else holds a reference to the same object.

**The general principle: a test must not depend on what ran before it.** Global mutable state is the usual culprit, and this is a textbook instance of it. It is also an argument for the repository pattern from `learn/13` — with storage behind an interface, tests inject a fresh instance instead of reaching into a module global.

### 3. Fixtures — setup, teardown, and the `yield`

A pytest fixture is a function that provides something to a test, or does setup and teardown around it.

```python
@pytest.fixture
def client():
    return TestClient(app)

def test_health(client):          # requested by parameter name
    assert client.get("/health").status_code == 200
```

The parameter name is the wiring — pytest matches the argument to a fixture of that name. There is no registration or import.

With `yield`, everything before is setup and everything after is teardown:

```python
@pytest.fixture
def thing():
    t = make()      # setup
    yield t         # the test runs here
    t.cleanup()     # teardown, runs even if the test fails
```

Fixtures have **scopes** — `function` (default, fresh per test), `module`, `session`. Default to `function`; a broader scope reintroduces exactly the shared-state problem you are trying to avoid.

Fixtures used across multiple test files go in `conftest.py`, which pytest loads automatically.

### 4. Arrange–Act–Assert

The shape of a readable test:

```python
def test_delete_removes_the_link(client):
    created = client.post("/links", json={...}).json()   # arrange
    response = client.delete(f"/links/{created['id']}")  # act
    assert response.status_code == 200                   # assert
    assert client.get(f"/links/{created['id']}").status_code == 404
```

One behaviour per test. When a test fails, its *name* should tell you what broke without reading the body — `test_delete_removes_the_link` beats `test_delete_2`.

### 5. Test the failure paths, not just the happy path

Bugs cluster at edges. The two 404s in this API are worth explicit tests:

- `GET /links/999` on an empty store → 404
- `DELETE /links/999` → 404

And worth considering: what does `POST /links` do with a missing required field? FastAPI returns **422**, not 400 — Pydantic's validation error. Asserting that documents the actual contract, and it is the kind of thing that surprises API consumers.

### 6. What `uv add --dev` does

```bash
uv add --dev pytest httpx
```

`--dev` puts these in a dependency group that is **not installed in production**. They land under `[dependency-groups]` in `pyproject.toml` rather than `[project.dependencies]`.

That matters for the Dockerfile: `uv sync --frozen --no-install-project` installs only the default dependencies, so `pytest` never enters the runtime image. Test tooling has no business shipping to production — it is dead weight and extra attack surface.

## Your steps

1. **Add the dependencies** — from WSL, where `uv` lives:

   ```bash
   wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub/links-service && uv add --dev pytest httpx"
   ```

   This updates `pyproject.toml` *and* `uv.lock`. Commit both.

2. **Create `links-service/tests/`** with an empty `__init__.py`, so `app` imports resolve consistently.

3. **Write the reset fixture first**, in `conftest.py` or at the top of the test file. Get this right before writing any test, or you will spend the afternoon debugging order-dependence.

4. **Write one test and run it.** Start with `/health` — trivial, and it proves your imports and fixtures work before you write five more against a broken setup.

5. **Then the CRUD tests**, one behaviour each: create returns an id; list reflects a create; get returns the created link; delete removes it; get on a missing id is 404; delete on a missing id is 404.

6. **Deliberately re-break `C-01`** — change `= new_link` back to `= link`, run the suite, watch it fail, change it back. That is the proof your tests are actually testing something. A suite that passes against a known bug is worse than no suite.

## Running them

```bash
wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub/links-service && uv run pytest -v"
```

Useful flags as you go:

| Flag | Does |
|---|---|
| `-v` | One line per test with its name |
| `-x` | Stop at the first failure |
| `-k create` | Run only tests whose name matches `create` |
| `-p no:randomly` | Disable any random ordering, if you add that plugin |
| `--tb=short` | Shorter tracebacks |

**Then run it twice in a row, and run it with `-p no:cacheprovider`.** If the second run fails when the first passed, you have leaking state.

## Gotchas

- **Module-level `links_db` and `next_id` leak between tests.** The single biggest trap here. Reset fixture, `autouse=True`.
- **`main.next_id = 1` rebinds a module attribute** — make sure you are setting it on the module object (`main.next_id`), not on a local import (`from app.main import next_id` copies the value and setting it does nothing).
- **Import path matters.** Run pytest from `links-service/`, so `app.main` resolves. An `__init__.py` in `tests/` avoids a class of collection oddities.
- **`TestClient` needs `httpx`.** The error if it is missing is not obvious.
- **Do not assert on hardcoded ids** unless you reset `next_id`. Use the id returned by the create call.
- **422 vs 400.** FastAPI validation failures are 422. Assert what the framework actually does.
- **Keep test deps out of the image.** `--dev`, and verify with `docker run --rm links-service:dev python -c "import pytest"` — it should fail.

## Going deeper

- [FastAPI testing](https://fastapi.tiangolo.com/tutorial/testing/) — the canonical `TestClient` intro
- [pytest fixtures](https://docs.pytest.org/en/stable/how-to/fixtures.html) — scopes, `autouse`, `yield` teardown
- [pytest good practices](https://docs.pytest.org/en/stable/explanation/goodpractices.html) — layout and import modes
- [uv dependency groups](https://docs.astral.sh/uv/concepts/projects/dependencies/#development-dependencies)
- [`monkeypatch`](https://docs.pytest.org/en/stable/how-to/monkeypatch.html) — the tidier way to patch module state, worth knowing once the reset fixture starts feeling crude

---

**Ask before you write** if any of the above is unclear — particularly fixtures and the reset. That conversation is the point of the exercise, not the file that comes out of it.
